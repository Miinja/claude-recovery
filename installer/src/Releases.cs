// Downloads the images from the project's GitHub releases.
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

        /// <summary>Image of the requested edition in the latest published release.</summary>
        public static ReleaseImage Latest(string edition)
        {
            string json;
            try { json = GetText(Api); }
            catch (WebException e)
            {
                var http = e.Response as HttpWebResponse;
                if (http != null && http.StatusCode == HttpStatusCode.NotFound)
                    throw new IOException(L.T("Aucune release publiée pour l'instant sur github.com/" + Repo + ".\nUtilisez « Fichier image local… » si vous avez déjà une image.",
                                              "No release published yet on github.com/" + Repo + ".\nUse \"Local image file…\" if you already have an image."));
                throw new IOException(L.T("GitHub est injoignable : ", "GitHub is unreachable: ") + e.Message);
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
                throw new IOException(L.T("La release " + image.Tag + " ne contient pas l'image « " + edition + " ».",
                                          "Release " + image.Tag + " does not contain the \"" + edition + "\" image."));
            return image;
        }

        /// <summary>
        /// Downloads the image into the temporary folder and returns the path of the
        /// verified file. An image already there with the right checksum is reused, and
        /// an interrupted download is resumed where it stopped, across restarts of the
        /// installer too: the partial file carries the checksum of the release it
        /// belongs to, so a newer release never resumes an older one.
        /// </summary>
        public static string Download(ReleaseImage image, string edition, Action<string, long, long> progress)
        {
            string dir = Path.Combine(Path.GetTempPath(), "ClaudeRecovery");
            Directory.CreateDirectory(dir);
            string path = Path.Combine(dir, AssetName(edition));

            string expected = GetText(image.ShaUrl).Trim().Split(' ', '\t')[0].ToLowerInvariant();
            if (expected.Length != 64) throw new IOException(L.T("Empreinte publiée illisible.", "The published checksum is unreadable."));

            if (File.Exists(path) && new FileInfo(path).Length == image.Size
                && Imaging.Sha256File(path, delegate(long d, long t) { progress(L.T("Vérification de l'image déjà téléchargée", "Checking the image already downloaded"), d, t); }) == expected)
                return path;

            string partial = path + "." + expected.Substring(0, 16) + ".part";
            foreach (string old in Directory.GetFiles(dir, Path.GetFileName(path) + ".*.part"))
                if (!string.Equals(old, partial, StringComparison.OrdinalIgnoreCase)) { try { File.Delete(old); } catch (IOException) { } }

            const int MaxAttempts = 6;
            for (int attempt = 1; ; attempt++)
            {
                try
                {
                    Fetch(image, partial, progress);
                    break;
                }
                catch (Exception e)
                {
                    if (!(e is WebException) && !(e is IOException)) throw;
                    if (attempt >= MaxAttempts)
                        throw new IOException(L.T("Le téléchargement a été interrompu : ", "The download was interrupted: ") + e.Message
                            + L.T("\nRelancez l'écriture : il reprendra là où il s'est arrêté.", "\nStart the write again: it will resume where it stopped."));
                    progress(L.T("Connexion interrompue, reprise…", "Connection lost, resuming…"), 0, 0);
                    System.Threading.Thread.Sleep(3000);
                }
            }

            string actual = Imaging.Sha256File(partial, delegate(long d, long t) { progress(L.T("Vérification du téléchargement", "Checking the download"), d, t); });
            if (actual != expected)
            {
                File.Delete(partial);
                throw new IOException(L.T("L'image téléchargée est corrompue (empreinte incorrecte). Recommencez.",
                                          "The downloaded image is corrupted (wrong checksum). Try again."));
            }
            if (File.Exists(path)) File.Delete(path);
            File.Move(partial, path);
            return path;
        }

        /// <summary>One download pass: continues the partial file if the server allows it.</summary>
        static void Fetch(ReleaseImage image, string partial, Action<string, long, long> progress)
        {
            long have = File.Exists(partial) ? new FileInfo(partial).Length : 0;
            if (have > image.Size) { File.Delete(partial); have = 0; }
            if (have == image.Size && have > 0) return;

            HttpWebRequest req = Request(image.IsoUrl);
            req.ReadWriteTimeout = 30000;
            if (have > 0) req.AddRange(have);
            using (var resp = (HttpWebResponse)req.GetResponse())
            {
                // 206: the server continues from where we are. 200: it sends everything again.
                bool resumed = have > 0 && resp.StatusCode == HttpStatusCode.PartialContent;
                if (!resumed) have = 0;
                using (Stream input = resp.GetResponseStream())
                using (var output = new FileStream(partial, resumed ? FileMode.Append : FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20))
                {
                    var buf = new byte[1 << 20];
                    long done = have;
                    int n;
                    while ((n = input.Read(buf, 0, buf.Length)) > 0)
                    {
                        output.Write(buf, 0, n);
                        done += n;
                        progress(L.T("Téléchargement de l'image ", "Downloading image ") + image.Tag, done, image.Size);
                    }
                    if (done < image.Size) throw new IOException(L.T("connexion coupée", "connection closed"));
                }
            }
        }
    }
}
