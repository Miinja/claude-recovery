// Copies the image to the key, writes the settings block, reads back to verify.
// Works on Streams: the same logic serves the key and the tests on a file.
using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace ClaudeRecovery
{
    public static class Imaging
    {
        public const int Chunk = 4 * 1024 * 1024;
        public const int BlobArea = 1024 * 1024;       // area reserved for the settings block
        public const int BlobMax = 60 * 1024;
        const string Magic = "CRCFGv01";

        public static string Hex(byte[] hash)
        {
            var sb = new StringBuilder(hash.Length * 2);
            foreach (byte b in hash) sb.Append(b.ToString("x2"));
            return sb.ToString();
        }

        public static string Sha256File(string path, Action<long, long> progress)
        {
            using (var sha = SHA256.Create())
            using (var f = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, Chunk))
            {
                var buf = new byte[Chunk];
                long done = 0;
                int n;
                while ((n = f.Read(buf, 0, buf.Length)) > 0)
                {
                    sha.TransformBlock(buf, 0, n, null, 0);
                    done += n;
                    if (progress != null) progress(done, f.Length);
                }
                sha.TransformFinalBlock(buf, 0, 0);
                return Hex(sha.Hash);
            }
        }

        /// <summary>Offset of the settings block: the 1 MiB boundary after the image.</summary>
        public static long BlobOffset(long imageLength)
        {
            return ((imageLength + BlobArea - 1) / BlobArea) * BlobArea;
        }

        /// <summary>A NAME='value' line that is safe to source from a shell.</summary>
        public static string EnvLine(string name, string value)
        {
            if (value.IndexOf('\n') >= 0 || value.IndexOf('\r') >= 0)
                throw new ArgumentException("Valeur sur plusieurs lignes : " + name);
            return name + "='" + value.Replace("'", "'\\''") + "'\n";
        }

        /// <summary>1 MiB block: CRCFGv01\n size\n sha256\n content, padded with zeros.</summary>
        public static byte[] BuildBlob(string envText)
        {
            byte[] payload = new UTF8Encoding(false).GetBytes(envText);
            if (payload.Length > BlobMax) throw new ArgumentException("Réglages trop volumineux.");
            string sum;
            using (var sha = SHA256.Create()) sum = Hex(sha.ComputeHash(payload));
            byte[] header = Encoding.ASCII.GetBytes(Magic + "\n" + payload.Length + "\n" + sum + "\n");
            var blob = new byte[BlobArea];
            Buffer.BlockCopy(header, 0, blob, 0, header.Length);
            Buffer.BlockCopy(payload, 0, blob, header.Length, payload.Length);
            return blob;
        }

        /// <summary>
        /// Writes the image at the start of the target, then the settings block (or zeros,
        /// to erase the one from an earlier write). Returns the SHA-256 of what was written.
        /// </summary>
        public static string Write(string imagePath, Stream target, byte[] blob, Action<long, long> progress)
        {
            using (var sha = SHA256.Create())
            using (var src = new FileStream(imagePath, FileMode.Open, FileAccess.Read, FileShare.Read, Chunk))
            {
                long total = src.Length, done = 0;
                var buf = new byte[Chunk];
                target.Position = 0;
                while (done < total)
                {
                    int n = 0, r;
                    while (n < buf.Length && (r = src.Read(buf, n, buf.Length - n)) > 0) n += r;
                    if (n == 0) break;
                    sha.TransformBlock(buf, 0, n, null, 0);
                    // A raw disk only accepts multiples of the sector size.
                    int padded = (n + 4095) / 4096 * 4096;
                    if (padded > n) Array.Clear(buf, n, padded - n);
                    target.Write(buf, 0, padded);
                    done += n;
                    if (progress != null) progress(done, total);
                }
                sha.TransformFinalBlock(buf, 0, 0);

                target.Position = BlobOffset(total);
                byte[] area = blob ?? new byte[BlobArea];
                target.Write(area, 0, area.Length);
                target.Flush();
                return Hex(sha.Hash);
            }
        }

        /// <summary>Reads the target back and compares it with the expected checksum and the block written.</summary>
        public static bool Verify(Stream target, long imageLength, string expectedSha, byte[] blob, Action<long, long> progress)
        {
            using (var sha = SHA256.Create())
            {
                var buf = new byte[Chunk];
                long done = 0;
                target.Position = 0;
                while (done < imageLength)
                {
                    // Reads in multiples of the sector size; only the useful part is hashed.
                    int want = (int)Math.Min(buf.Length, (imageLength - done + 4095) / 4096 * 4096);
                    int n = 0, r;
                    while (n < want && (r = target.Read(buf, n, want - n)) > 0) n += r;
                    if (n == 0) return false;
                    int useful = (int)Math.Min(n, imageLength - done);
                    sha.TransformBlock(buf, 0, useful, null, 0);
                    done += useful;
                    if (progress != null) progress(done, imageLength);
                }
                sha.TransformFinalBlock(buf, 0, 0);
                if (Hex(sha.Hash) != expectedSha) return false;

                byte[] expected = blob ?? new byte[BlobArea];
                var back = new byte[BlobArea];
                target.Position = BlobOffset(imageLength);
                int got = 0, x;
                while (got < back.Length && (x = target.Read(back, got, back.Length - got)) > 0) got += x;
                if (got != back.Length) return false;
                for (int i = 0; i < back.Length; i++) if (back[i] != expected[i]) return false;
                return true;
            }
        }
    }
}
