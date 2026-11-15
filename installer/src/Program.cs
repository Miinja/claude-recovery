// Point d'entree de l'installeur Claude Recovery.
using System;
using System.IO;
using System.Security.Principal;
using System.Windows.Forms;

namespace ClaudeRecovery
{
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            if (args.Length >= 1 && args[0] == "--selftest") return SelfTest(args);
            if (args.Length >= 4 && args[0] == "--probe")
            {
                // --probe <adresse> <jeton> <fichier> : le test du serveur de journaux, sans fenetre
                File.WriteAllText(args[3], SettingsDialog.Probe(args[1], args[2]));
                return 0;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Theme.Init();
            if (args.Length >= 2 && args[0] == "--screenshot")
            {
                // --screenshot <png> [fr|en] [etat] : rendu de la fenetre (ou d'un dialogue)
                // dans un PNG, pour controler la mise en page. Etats : voir MainForm.Demo.
                if (args.Length >= 3) L.Lang = args[2] == "fr" ? "fr" : "en";
                using (var form = new MainForm())
                {
                    form.Show();
                    Form shown = form.Demo(args.Length >= 4 ? args[3] : "");
                    if (shown != form) shown.Show(form);
                    Application.DoEvents();
                    using (var bmp = new System.Drawing.Bitmap(shown.Width, shown.Height))
                    {
                        shown.DrawToBitmap(bmp, new System.Drawing.Rectangle(0, 0, shown.Width, shown.Height));
                        bmp.Save(args[1], System.Drawing.Imaging.ImageFormat.Png);
                    }
                    if (shown != form) shown.Dispose();
                }
                return 0;
            }
            if (!new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator))
            {
                MessageBox.Show(L.T("L'écriture d'une clé USB demande les droits d'administrateur.\nFaites un clic droit sur le programme, puis « Exécuter en tant qu'administrateur ».",
                                    "Writing a USB key requires administrator rights.\nRight-click the program, then \"Run as administrator\"."),
                    "Claude Recovery", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return 1;
            }
            Application.Run(new MainForm());
            return 0;
        }

        // --selftest <image> <fichier cible> : exerce la copie, le bloc de reglages et la
        // relecture sur un simple fichier, et liste les cles USB. N'ecrit sur aucun disque.
        static int SelfTest(string[] args)
        {
            try
            {
                var log = new StringWriter();
                foreach (UsbDisk d in Disks.ListUsb()) log.WriteLine("usb: " + d);
                if (args.Length >= 3)
                {
                    string env = Imaging.EnvLine("RECOVERY_COMPANY", "L'atelier \"test\" $HOME `x`")
                               + Imaging.EnvLine("RECOVERY_KEY_ID", "cle01")
                               + Imaging.EnvLine("RECOVERY_LOG_URL", "https://logs.exemple.lan")
                               + Imaging.EnvLine("RECOVERY_LOG_TOKEN", "0123456789abcdef0123456789abcdef");
                    byte[] blob = Imaging.BuildBlob(env);
                    long length = new FileInfo(args[1]).Length;
                    using (var target = new FileStream(args[2], FileMode.Create, FileAccess.ReadWrite))
                    {
                        string sha = Imaging.Write(args[1], target, blob, null);
                        log.WriteLine("sha256: " + sha);
                        log.WriteLine("blob_offset: " + Imaging.BlobOffset(length));
                        log.WriteLine("verify: " + Imaging.Verify(target, length, sha, blob, null));
                        target.Position = 5; target.WriteByte(0xFF);          // alteration volontaire
                        log.WriteLine("verify_after_corruption: " + Imaging.Verify(target, length, sha, blob, null));
                    }
                }
                File.WriteAllText(args.Length >= 4 ? args[3] : "selftest.log", log.ToString());
                return 0;
            }
            catch (Exception e)
            {
                File.WriteAllText("selftest-error.log", e.ToString());
                return 2;
            }
        }
    }
}
