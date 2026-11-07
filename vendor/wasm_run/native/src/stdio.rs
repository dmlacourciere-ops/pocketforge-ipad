//! Byte-preserving WASI output capture with race-safe late subscription replay.

pub(crate) trait OutputSink: Send + Sync {
    fn add(&self, bytes: Vec<u8>) -> bool;
    fn close(&self);
}

#[derive(Default)]
pub(crate) struct CapturedOutput {
    bytes: Vec<u8>,
    sink: Option<Box<dyn OutputSink>>,
}

impl CapturedOutput {
    pub(crate) fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    pub(crate) fn write(&mut self, bytes: &[u8]) {
        self.bytes.extend_from_slice(bytes);
        if !bytes.is_empty() {
            if let Some(sink) = &self.sink {
                if !sink.add(bytes.to_vec()) {
                    self.sink = None;
                }
            }
        }
    }

    pub(crate) fn subscribe(&mut self, sink: Box<dyn OutputSink>) {
        if let Some(previous) = self.sink.take() {
            previous.close();
        }
        // FRB can schedule stream registration after a fast guest has already
        // written output. Publish that prefix before accepting subsequent writes.
        if self.bytes.is_empty() || sink.add(self.bytes.clone()) {
            self.sink = Some(sink);
        }
    }
}

impl Drop for CapturedOutput {
    fn drop(&mut self) {
        if let Some(sink) = self.sink.take() {
            sink.close();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[derive(Default)]
    struct Received {
        chunks: Vec<Vec<u8>>,
        closes: usize,
    }

    struct Sink(Arc<Mutex<Received>>);
    impl OutputSink for Sink {
        fn add(&self, bytes: Vec<u8>) -> bool {
            self.0.lock().unwrap().chunks.push(bytes);
            true
        }
        fn close(&self) {
            self.0.lock().unwrap().closes += 1;
        }
    }

    #[test]
    fn output_written_before_subscription_is_replayed_then_streamed_once() {
        let received = Arc::new(Mutex::new(Received::default()));
        let mut output = CapturedOutput::default();
        output.write(b"ripgrep ");
        output.subscribe(Box::new(Sink(received.clone())));
        output.write(b"14.1\n");
        assert_eq!(
            received.lock().unwrap().chunks,
            [b"ripgrep ".to_vec(), b"14.1\n".to_vec()]
        );
        assert_eq!(output.bytes(), b"ripgrep 14.1\n");
    }

    #[test]
    fn subscription_before_guest_write_preserves_binary_chunks_and_closes_on_drop() {
        let received = Arc::new(Mutex::new(Received::default()));
        {
            let mut output = CapturedOutput::default();
            output.subscribe(Box::new(Sink(received.clone())));
            output.write(&[0, 255, 226]);
            output.write(&[130, 172, 10]);
            assert_eq!(output.bytes(), [0, 255, 226, 130, 172, 10]);
            assert_eq!(
                received.lock().unwrap().chunks,
                [vec![0, 255, 226], vec![130, 172, 10]]
            );
        }
        assert_eq!(received.lock().unwrap().closes, 1);
    }

    #[test]
    fn separate_output_streams_do_not_mix_stdout_and_stderr() {
        let received_out = Arc::new(Mutex::new(Received::default()));
        let received_err = Arc::new(Mutex::new(Received::default()));
        let mut stdout = CapturedOutput::default();
        let mut stderr = CapturedOutput::default();
        stdout.subscribe(Box::new(Sink(received_out.clone())));
        stderr.write(b"error\n");
        stderr.subscribe(Box::new(Sink(received_err.clone())));
        stdout.write(b"result\n");
        assert_eq!(received_out.lock().unwrap().chunks, [b"result\n".to_vec()]);
        assert_eq!(received_err.lock().unwrap().chunks, [b"error\n".to_vec()]);
    }
}
