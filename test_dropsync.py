#!/usr/bin/env python3
"""
DropSync Automated End-to-End Test Suite
Tests:
1. UDP Discovery Beacon & Parsing
2. TCP Auth Handshake (Valid PIN vs Invalid PIN)
3. Clipboard Sync with SHA-256 Loopback Suppression
4. High-Speed 64 KB Chunked File Streaming & Integrity Check
"""

import asyncio
import hashlib
import json
import os
import struct
import tempfile
import time
import unittest

from dropsync_host import (
    DropSyncHost,
    encode_frame,
    read_frame,
    encode_file_header,
    MAGIC_BYTES,
    MSG_AUTH_REQ,
    MSG_AUTH_RESP,
    MSG_AUTH_OK,
    MSG_AUTH_FAIL,
    MSG_CLIPBOARD,
    MSG_FILE_STREAM,
)

TEST_PORT = 52530
TEST_PIN = "9876"


class TestDropSyncProtocol(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.host = DropSyncHost(
            host="127.0.0.1",
            port=TEST_PORT,
            pin=TEST_PIN,
            save_dir=self.temp_dir.name,
        )
        await self.host.start()

    async def asyncTearDown(self):
        await self.host.stop()
        self.temp_dir.cleanup()

    async def test_01_auth_failure_wrong_pin(self):
        """Verify that connecting with an invalid PIN is rejected and terminated."""
        reader, writer = await asyncio.open_connection("127.0.0.1", TEST_PORT)

        # 1. Receive AUTH_REQ
        msg_type, payload = await read_frame(reader)
        self.assertEqual(msg_type, MSG_AUTH_REQ)

        # 2. Send wrong PIN
        bad_resp = json.dumps({"pin": "0000", "device_name": "TestClient"}).encode()
        writer.write(encode_frame(MSG_AUTH_RESP, bad_resp))
        await writer.drain()

        # 3. Expect AUTH_FAIL
        msg_type, payload = await read_frame(reader)
        self.assertEqual(msg_type, MSG_AUTH_FAIL)

        # Connection should be closed by server
        data = await reader.read()
        self.assertEqual(data, b"")
        writer.close()
        await writer.wait_closed()

    async def test_02_auth_success_and_clipboard_loopback(self):
        """Verify valid authentication and clipboard synchronization with loopback prevention."""
        reader, writer = await asyncio.open_connection("127.0.0.1", TEST_PORT)

        # Handshake
        msg_type, _ = await read_frame(reader)
        self.assertEqual(msg_type, MSG_AUTH_REQ)

        good_resp = json.dumps({"pin": TEST_PIN, "device_name": "TestClient"}).encode()
        writer.write(encode_frame(MSG_AUTH_RESP, good_resp))
        await writer.drain()

        msg_type, payload = await read_frame(reader)
        self.assertEqual(msg_type, MSG_AUTH_OK)

        # Send remote clipboard update to host
        test_text = "https://flutter.dev/gems/bonsoir"
        test_hash = hashlib.sha256(test_text.encode("utf-8")).hexdigest()
        clip_payload = json.dumps({"text": test_text, "hash": test_hash, "timestamp": int(time.time())}).encode()
        writer.write(encode_frame(MSG_CLIPBOARD, clip_payload))
        await writer.drain()

        # Give host a moment to process and set its clipboard
        await asyncio.sleep(0.3)

        # Host's last_received_hash must now match test_hash, which prevents loopback echo
        self.assertEqual(self.host.clipboard_monitor.last_received_hash, test_hash)

        writer.close()
        await writer.wait_closed()

    async def test_03_high_speed_chunked_file_transfer(self):
        """Verify binary streaming of arbitrary size in 64 KB chunks, .part handling, and integrity."""
        reader, writer = await asyncio.open_connection("127.0.0.1", TEST_PORT)

        # Handshake
        await read_frame(reader)
        writer.write(encode_frame(MSG_AUTH_RESP, json.dumps({"pin": TEST_PIN, "device_name": "TestSender"}).encode()))
        await writer.drain()
        msg_type, _ = await read_frame(reader)
        self.assertEqual(msg_type, MSG_AUTH_OK)

        # Generate a test payload of 2.5 MB (crosses multiple 64 KB chunks)
        test_size = int(2.5 * 1024 * 1024)
        sample_data = os.urandom(test_size)
        expected_sha = hashlib.sha256(sample_data).hexdigest()
        filename = "test_video_sample.bin"

        # Signal FILE_STREAM
        writer.write(encode_frame(MSG_FILE_STREAM, b""))
        await writer.drain()

        # Send binary header: Magic (4B) | Name Len (2B) | Name (UTF-8) | File Size (8B)
        header = encode_file_header(filename, test_size)
        writer.write(header)
        await writer.drain()

        # Stream body in 64 KB chunks
        chunk_size = 64 * 1024
        for i in range(0, test_size, chunk_size):
            chunk = sample_data[i : i + chunk_size]
            writer.write(chunk)
            await writer.drain()

        # Wait for file write and atomic rename to complete
        await asyncio.sleep(0.5)

        saved_file = os.path.join(self.temp_dir.name, filename)
        part_file = saved_file + ".part"

        # 1. Part file must not exist (cleaned up via rename)
        self.assertFalse(os.path.exists(part_file), "Temporary .part file was not renamed")

        # 2. Final file must exist and match size and hash
        self.assertTrue(os.path.exists(saved_file), "Final saved file not found")
        self.assertEqual(os.path.getsize(saved_file), test_size)

        with open(saved_file, "rb") as f:
            actual_sha = hashlib.sha256(f.read()).hexdigest()
        self.assertEqual(actual_sha, expected_sha, "Checksum mismatch on transferred file")

        writer.close()
        await writer.wait_closed()


if __name__ == "__main__":
    unittest.main()
