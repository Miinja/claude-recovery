// Telechargement des images depuis les releases GitHub du projet.
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Web.Script.Serialization;

namespace ClaudeRecovery
{
    public sealed class ReleaseImage
    {
        public string Tag;
        public string IsoUrl;
        public string ShaUrl;
        public long Size;
    }

    public static class Releases
    {
        public const string Repo = "Miinja/claude-recovery";
        const string Api = "https://api.github.com/repos/" + Repo + "/releases/latest";
        const string Agent = "ClaudeRecoveryInstaller";

        static Releases()
        {
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;   // TLS 1.2
        }

        public static string AssetName(string edition)
        {
            return "claude-recovery-" + edition + ".iso";
        }

        static HttpWebRequest Request(string url)
        {
            var req = (HttpWebRequest)WebRequest.Create(url);
            req.UserAgent = Agent;
            req.Accept = "application/octet-stream, application/vnd.github+json";
            req.Timeout = 30000;
            return req;
        }

        static string GetText(string url)
        {
            using (WebResponse resp = Request(url).GetResponse())
            using (var reader = new StreamReader(resp.GetResponseStream()))
                return reader.ReadToEnd();
        }

        /// <summary>Image de l'edition demandee dans la derniere release publiee.</summary>
        public static ReleaseImage Latest(string edition)
        {
            string json;
            try { json = GetText(Api); }
            catch (WebException e)
            {
                var http = e.Response as HttpWebResponse;
                if (http != null && http.StatusCode == HttpStatusCode.NotFound)
                    throw new IOException("Aucune release publiée pour l'instant sur github.com/" + Repo + ".\nUtilisez « Fichier image local… » si vous avez déjà une image.");
                throw new IOException("GitHub est injoignable : " + e.Message);
            }

            var release = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json);
            var image = new ReleaseImage { Tag = Convert.ToString(release["tag_name"]) };
            string name = AssetName(edition);
            foreach (object o in (IEnumerable)release["assets"])
            {
                var asset = (Dictionary<string, object>)o;
                string assetName = Convert.ToString(asset["name"]);
                string url = Convert.ToString(asset["browser_download_url"]);
                if (assetName == name) { image.IsoUrl = url; image.Size = Convert.ToInt64(asset["size"]); }
                else if (assetName == name + ".sha256") image.ShaUrl = url;
            }
            if (image.IsoUrl == null || image.ShaUrl == null)
                throw new IOException("La release " + image.Tag + " ne contient pas l'image « " + edition + " ».");
            return image;
        }

        /// <summary>
        /// Telecharge l'image dans le dossier temporaire (ou reprend celle deja presente si
        /// son empreinte est bonne). Renvoie le chemin du fichier verifie.
        /// </summary>
        public static string Download(ReleaseImage image, string edition, Action<string, long, long> progress)
        {
            string dir = Path.Combine(Path.GetTempPath(), "ClaudeRecovery");
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, AssetName(edition));

            string expected = GetText(image.ShaUrl).Trim().Split(' ', '\t')[0].ToLowerInvariant();
            if (expected.Length != 64) throw new IOException("Empreinte publiée illisible.");

            if (File.Exists(path) && new FileInfo(path).Length == image.Size
                && Imaging.Sha256File(path, delegate(long d, long t) { progress("Vérification de l'image déjà téléchargée", d, t); }) == expected)
                return path;

            string partial = path + ".part";
            using (WebResponse resp = Request(image.IsoUrl).GetResponse())
            using (Stream input = resp.GetResponseStream())
            using (var output = new FileStream(partial, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20))
            {
                var buf = new byte[1 << 20];
                long done = 0;
                int n;
                while ((n = input.Read(buf, 0, buf.Length)) > 0)
                {
                    output.Write(buf, 0, n);
                    done += n;
                    progress("Téléchargement de l'image " + image.Tag, done, image.Size);
                }
            }

            string actual = Imaging.Sha256File(partial, delegate(long d, long t) { progress("Vérification du téléchargement", d, t); });
            if (actual != expected)
            {
                File.Delete(partial);
                throw new IOException("L'image téléchargée est corrompue (empreinte incorrecte). Recommencez.");
            }
            if (File.Exists(path)) File.Delete(path);
            File.Move(partial, path);
            return path;
        }
    }
}
