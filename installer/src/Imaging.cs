// Copie de l'image vers la cle, bloc de reglages, relecture de controle.
// Travaille sur des Stream : la meme logique sert a la cle et aux tests sur fichier.
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
        public const int BlobArea = 1024 * 1024;       // zone reservee au bloc de reglages
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

        /// <summary>Decalage du bloc de reglages : frontiere de 1 Mio qui suit l'image.</summary>
        public static long BlobOffset(long imageLength)
        {
            return ((imageLength + BlobArea - 1) / BlobArea) * BlobArea;
        }

        /// <summary>Ligne NOM='valeur' sure a inclure par un shell.</summary>
        public static string EnvLine(string name, string value)
        {
            if (value.IndexOf('\n') >= 0 || value.IndexOf('\r') >= 0)
                throw new ArgumentException("Valeur sur plusieurs lignes : " + name);
            return name + "='" + value.Replace("'", "'\\''") + "'\n";
        }

        /// <summary>Bloc de 1 Mio : CRCFGv01\n taille\n sha256\n contenu, complete par des zeros.</summary>
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
        /// Ecrit l'image au debut de la cible, puis le bloc de reglages (ou des zeros, pour
        /// effacer celui d'une ecriture precedente). Renvoie le SHA-256 de ce qui a ete ecrit.
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
                    // Un disque brut n'accepte que des multiples de la taille de secteur.
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

        /// <summary>Relit la cible et compare a l'empreinte attendue et au bloc ecrit.</summary>
        public static bool Verify(Stream target, long imageLength, string expectedSha, byte[] blob, Action<long, long> progress)
        {
            using (var sha = SHA256.Create())
            {
                var buf = new byte[Chunk];
                long done = 0;
                target.Position = 0;
                while (done < imageLength)
                {
                    // Lectures par multiples de secteur ; on ne hache que la partie utile.
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
