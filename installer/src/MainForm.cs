// The installer's window: three steps (edition, USB key, write), then the progress
// view and the final screen. The look is in Ui.cs.
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace CtrlZ
{
    public sealed class MainForm : Form
    {
        /// <summary>Above this size, the disk is flagged as suspicious for a USB key.</summary>
        public const long BigDisk = 130L * 1000 * 1000 * 1000;

        enum View { Setup, Busy, Done }

        // Layout, in pixels at 96 dpi
        const int W = 820, H = 500;
        static readonly int[] StepX = { 150, 410, 670 };
        const int IconY = 150, IconR = 36, ColW = 220;

        readonly Segmented segLang = new Segmented();
        readonly Segmented segEdition = new Segmented();
        readonly FlatButton btnDisk = new FlatButton();
        readonly FlatButton btnWrite = new FlatButton { Kind = ButtonKind.Accent };
        readonly FlatButton lnkSettings = new FlatButton { Kind = ButtonKind.Link };
        readonly FlatButton lnkLocal = new FlatButton { Kind = ButtonKind.Link };
        readonly FlatButton lnkHelp = new FlatButton { Kind = ButtonKind.Link };
        readonly FlatButton btnAgain = new FlatButton();
        readonly FlatButton btnClose = new FlatButton { Kind = ButtonKind.Accent };

        View view = View.Setup;
        UsbDisk disk;
        KeySettings settings = new KeySettings();
        string localImage;
        string status = "";
        bool statusIsError;
        string progressStep = "";
        long progressDone, progressTotal;

        public MainForm()
        {
            AutoScaleMode = AutoScaleMode.None;
            Font = Theme.F(9.5f);
            BackColor = Theme.Back;
            ForeColor = Theme.Text;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }
            ClientSize = new Size(Theme.S(W), Theme.S(H));
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);

            segLang.Font = Theme.Semi(8.5f);
            segLang.SetItems("FR", "EN");
            segLang.Selected = L.Lang == "fr" ? 0 : 1;
            segLang.SetBounds(Theme.S(W - 32 - 92), Theme.S(22), Theme.S(92), Theme.S(30));

            lnkHelp.Font = Theme.F(9f);
            lnkHelp.SetBounds(Theme.S(W - 32 - 92 - 16 - 110), Theme.S(25), Theme.S(110), Theme.S(24));

            int top = Theme.S(232), h = Theme.S(42);
            segEdition.SetBounds(Theme.S(StepX[0] - ColW / 2), top, Theme.S(ColW), h);
            btnDisk.SetBounds(Theme.S(StepX[1] - ColW / 2), top, Theme.S(ColW), h);
            btnWrite.SetBounds(Theme.S(StepX[2] - ColW / 2), top, Theme.S(ColW), h);
            lnkSettings.SetBounds(Theme.S(StepX[0] - ColW / 2), Theme.S(348), Theme.S(ColW), Theme.S(24));
            lnkLocal.Font = Theme.F(9f);
            lnkLocal.SetBounds(Theme.S(W - 32 - 190), Theme.S(424), Theme.S(190), Theme.S(24));
            btnAgain.SetBounds(Theme.S(W / 2 - 200), Theme.S(372), Theme.S(195), h);
            btnClose.SetBounds(Theme.S(W / 2 + 5), Theme.S(372), Theme.S(195), h);
            Controls.AddRange(new Control[] { segLang, lnkHelp, segEdition, btnDisk, btnWrite, lnkSettings, lnkLocal, btnAgain, btnClose });

            segLang.SelectedChanged += delegate { L.Lang = segLang.Selected == 0 ? "fr" : "en"; ApplyTexts(); };
            segEdition.SelectedChanged += delegate { ClearStatus(); ApplyTexts(); };
            lnkHelp.Click += delegate { try { System.Diagnostics.Process.Start(HelpUrl); } catch (Exception) { } };
            btnDisk.Click += delegate { ChooseDisk(); };
            lnkSettings.Click += delegate { EditSettings(); };
            lnkLocal.Click += delegate { ChooseLocal(); };
            btnWrite.Click += async delegate { await WriteKey(); };
            btnAgain.Click += delegate { disk = null; ClearStatus(); SetView(View.Setup); };
            btnClose.Click += delegate { Close(); };
            Load += delegate { ApplyTexts(); };
        }

        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Theme.DarkTitleBar(this); }

        static string HelpUrl
        {
            get { return "https://github.com/" + Releases.Repo + "/blob/main/" + L.T("README.fr.md#cr%C3%A9er-une-cl%C3%A9", "README.md#creating-a-key"); }
        }

        string Edition { get { return segEdition.Selected == 1 ? "business" : "personal"; } }

        static string EditionName(string edition)
        {
            return edition == "business" ? L.T("entreprise", "business") : L.T("particulier", "personal");
        }

        void ClearStatus() { status = ""; statusIsError = false; }

        void SetView(View v) { view = v; ApplyTexts(); }

        /// <summary>Sets the texts in the current language and shows the controls of the view.</summary>
        void ApplyTexts()
        {
            Text = "Ctrl-Z";
            segEdition.SetItems(L.T("Particulier", "Personal"), L.T("Entreprise", "Business"));
            btnDisk.Text = disk != null ? disk.Model : L.T("Choisir la clé USB", "Select the USB key");
            btnDisk.Kind = disk != null ? ButtonKind.Ghost : ButtonKind.Accent;
            btnWrite.Text = L.T("Écrire la clé", "Write the key");
            btnWrite.Enabled = disk != null;
            lnkSettings.Text = settings.Complete
                ? L.T("Réglages : ", "Settings: ") + settings.KeyId + L.T("  ·  modifier", "  ·  edit")
                : L.T("Remplir les réglages…", "Fill in the settings…");
            lnkLocal.Text = localImage != null ? L.T("Revenir à la release", "Back to the release") : L.T("Utiliser un fichier local…", "Use a local file…");
            lnkHelp.Text = L.T("Aide en ligne", "Online help");
            btnAgain.Text = L.T("Créer une autre clé", "Create another key");
            btnClose.Text = L.T("Fermer", "Close");

            bool setup = view == View.Setup;
            segEdition.Visible = btnDisk.Visible = btnWrite.Visible = lnkLocal.Visible = setup;
            lnkSettings.Visible = setup && Edition == "business";
            btnAgain.Visible = btnClose.Visible = view == View.Done;
            segLang.Enabled = view != View.Busy;
            Invalidate();
        }

        // --- Drawing ---------------------------------------------------------------

        static void Draw(Graphics g, string text, Font font, Color color, int x, int y, int w, int h, TextFormatFlags flags)
        {
            TextRenderer.DrawText(g, text, font, new Rectangle(Theme.S(x), Theme.S(y), Theme.S(w), Theme.S(h)), color, flags);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Theme.Back);

            using (Font title = Theme.Semi(13f))
                Draw(g, "Ctrl-Z", title, Theme.Text, 32, 20, 300, 32, TextFormatFlags.NoPrefix | TextFormatFlags.VerticalCenter);
            using (Font small = Theme.F(8.5f))
            {
                Draw(g, BuildInfo.Version, small, Theme.Muted, 104, 22, 120, 32, TextFormatFlags.NoPrefix | TextFormatFlags.VerticalCenter);
                Draw(g, "powered by Claude Code", small, Theme.Muted, 32, 50, 300, 18, TextFormatFlags.NoPrefix);
            }

            // State of the three steps: 2 = done, 1 = current, 0 = to come
            int[] state = { 2, disk != null ? 2 : 1, disk != null ? 1 : 0 };
            if (view == View.Busy) state = new[] { 2, 2, 1 };
            if (view == View.Done) state = new[] { 2, 2, 2 };

            using (var pen = new Pen(Theme.Line, Theme.S(2f)))
            using (var penDone = new Pen(view == View.Done ? Theme.Ok : Theme.Accent, Theme.S(2f)))
                for (int i = 0; i < 2; i++)
                    g.DrawLine(state[i + 1] >= 1 && state[i] == 2 ? penDone : pen,
                        Theme.S(StepX[i] + IconR + 14), Theme.S(IconY), Theme.S(StepX[i + 1] - IconR - 14), Theme.S(IconY));

            string[] captions = { L.T("ÉDITION", "EDITION"), L.T("CLÉ USB", "USB KEY"), L.T("ÉCRITURE", "WRITE") };
            using (Font cap = Theme.Semi(8.5f))
                for (int i = 0; i < 3; i++)
                {
                    DrawStepIcon(g, i, state[i]);
                    Draw(g, captions[i], cap, state[i] == 0 ? Theme.Line : Theme.Muted, StepX[i] - ColW / 2, 196, ColW, 22, Theme.Center);
                }

            if (view == View.Setup) PaintSetup(g);
            else if (view == View.Busy) PaintBusy(g);
            else PaintDone(g);
        }

        void DrawStepIcon(Graphics g, int index, int state)
        {
            float cx = Theme.S((float)StepX[index]), cy = Theme.S((float)IconY), r = Theme.S((float)IconR);
            Color main = view == View.Done ? Theme.Ok : Theme.Accent;
            Color glyph;
            var circle = new RectangleF(cx - r, cy - r, 2 * r, 2 * r);
            if (state == 2)
            {
                using (var b = new SolidBrush(main)) g.FillEllipse(b, circle);
                glyph = Theme.Back;
            }
            else
            {
                using (var b = new SolidBrush(Theme.Surface)) g.FillEllipse(b, circle);
                using (var p = new Pen(state == 1 ? main : Theme.Line, Theme.S(2f))) g.DrawEllipse(p, circle);
                glyph = state == 1 ? Theme.Text : Theme.Muted;
            }
            float u = r / 36f;       // unit of the pictogram
            using (var pen = new Pen(glyph, 2.6f * u) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
            using (var brush = new SolidBrush(glyph))
            {
                if (view == View.Done)
                {
                    g.DrawLines(pen, new[] { new PointF(cx - 12 * u, cy + 1 * u), new PointF(cx - 3 * u, cy + 10 * u), new PointF(cx + 13 * u, cy - 9 * u) });
                }
                else if (index == 0)
                {   // disc
                    g.DrawEllipse(pen, cx - 15 * u, cy - 15 * u, 30 * u, 30 * u);
                    g.FillEllipse(brush, cx - 4.5f * u, cy - 4.5f * u, 9 * u, 9 * u);
                }
                else if (index == 1)
                {   // USB key
                    using (GraphicsPath body = Theme.Round(new RectangleF(cx - 9 * u, cy - 6 * u, 18 * u, 24 * u), 4 * u)) g.DrawPath(pen, body);
                    g.DrawLines(pen, new[] { new PointF(cx - 6 * u, cy - 6 * u), new PointF(cx - 6 * u, cy - 17 * u), new PointF(cx + 6 * u, cy - 17 * u), new PointF(cx + 6 * u, cy - 6 * u) });
                    g.FillEllipse(brush, cx - 3.6f * u, cy - 13 * u, 2.6f * u, 2.6f * u);
                    g.FillEllipse(brush, cx + 1.0f * u, cy - 13 * u, 2.6f * u, 2.6f * u);
                }
                else
                {   // lightning bolt
                    g.FillPolygon(brush, new[] {
                        new PointF(cx + 4 * u, cy - 18 * u), new PointF(cx - 11 * u, cy + 3 * u), new PointF(cx - 1 * u, cy + 3 * u),
                        new PointF(cx - 4 * u, cy + 18 * u), new PointF(cx + 11 * u, cy - 3 * u), new PointF(cx + 1 * u, cy - 3 * u) });
                }
            }
        }

        void PaintSetup(Graphics g)
        {
            const TextFormatFlags sub = TextFormatFlags.HorizontalCenter | TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix;
            string edition = Edition == "business"
                ? L.T("Pour un technicien. Chaque commande est journalisée et envoyée au serveur de l'entreprise.",
                      "For a technician. Every command is logged and sent to the company's server.")
                : L.T("Pour récupérer ses propres fichiers. Claude explique chaque étape, rien n'est envoyé à un serveur.",
                      "To recover your own files. Claude explains every step; nothing is sent to a server.");
            string key = disk != null
                ? UsbDisk.FormatSize(disk.Size) + "  ·  " + L.T("disque ", "disk ") + disk.Number + "\n" + L.T("Elle sera entièrement effacée.", "It will be completely erased.")
                : L.T("Branchez la clé à utiliser.\nElle sera entièrement effacée.", "Plug in the key to use.\nIt will be completely erased.");
            string write = L.T("Téléchargement de l'image, écriture, puis relecture de contrôle.",
                               "Image download, write, then a read-back check.");
            using (Font f = Theme.F(9f))
            {
                Draw(g, edition, f, Theme.Muted, StepX[0] - ColW / 2, 286, ColW, 58, sub);
                Draw(g, key, f, disk != null && disk.Size > BigDisk ? Theme.Danger : Theme.Muted, StepX[1] - ColW / 2, 286, ColW, 58, sub);
                Draw(g, write, f, Theme.Muted, StepX[2] - ColW / 2, 286, ColW, 58, sub);

                using (var pen = new Pen(Theme.Surface, 1f)) g.DrawLine(pen, Theme.S(32), Theme.S(408), Theme.S(W - 32), Theme.S(408));
                string source = localImage != null
                    ? L.T("Image : ", "Image: ") + Path.GetFileName(localImage)
                    : L.T("Image : dernière release de github.com/", "Image: latest release of github.com/") + Releases.Repo;
                Draw(g, source, f, Theme.Muted, 32, 424, W - 64 - 200, 24, TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
                if (status.Length > 0)
                    Draw(g, status, f, statusIsError ? Theme.Danger : Theme.Muted, 32, 452, W - 64, 36, TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            }
        }

        void PaintBusy(Graphics g)
        {
            double ratio = progressTotal > 0 ? Math.Min(1.0, (double)progressDone / progressTotal) : 0;
            using (Font big = Theme.Semi(22f))
                Draw(g, progressTotal > 0 ? ((int)(ratio * 100)) + " %" : "…", big, Theme.Text, 0, 232, W, 48, Theme.Center);
            var track = new RectangleF(Theme.S(150f), Theme.S(296f), Theme.S((float)(W - 300)), Theme.S(8f));
            Theme.FillRound(g, Theme.Surface, track, Theme.S(4f));
            if (ratio > 0)
                Theme.FillRound(g, Theme.Accent, new RectangleF(track.X, track.Y, Math.Max(track.Height, (float)(track.Width * ratio)), track.Height), Theme.S(4f));
            string detail = progressStep;
            if (progressTotal > 0) detail += "  ·  " + UsbDisk.FormatSize(progressDone) + " / " + UsbDisk.FormatSize(progressTotal);
            using (Font f = Theme.F(10f))
                Draw(g, detail, f, Theme.Text, 0, 322, W, 26, Theme.Center);
            using (Font f = Theme.F(9f))
                Draw(g, L.T("Ne retirez pas la clé et ne fermez pas cette fenêtre.", "Do not remove the key or close this window."),
                    f, Theme.Muted, 0, 356, W, 24, Theme.Center);
        }

        void PaintDone(Graphics g)
        {
            using (Font big = Theme.Semi(16f))
                Draw(g, L.T("La clé est prête", "The key is ready"), big, Theme.Text, 0, 228, W, 40, Theme.Center);
            using (Font f = Theme.F(10f))
            {
                Draw(g, L.T("Démarrez un PC dessus, puis tapez", "Boot a PC from it, then type"), f, Theme.Muted, 0, 274, W, 24, Theme.Center);
                Draw(g, L.T("Au premier démarrage, la clé crée son espace de persistance.", "On first boot, the key creates its persistence space."),
                    f, Theme.Muted, 0, 334, W, 24, Theme.Center);
            }
            using (Font mono = new Font("Consolas", 11f))
            {
                var box = new RectangleF(Theme.S(W / 2f - 100), Theme.S(300f), Theme.S(200f), Theme.S(28f));
                Theme.FillRound(g, Theme.Surface, box, Theme.S(6f));
                TextRenderer.DrawText(g, "ctrlz", mono, Rectangle.Round(box), Theme.Text, Theme.Center);
            }
        }

        // --- Actions ---------------------------------------------------------------

        void ChooseDisk()
        {
            using (var dlg = new DiskDialog())
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                disk = dlg.Selected;
            }
            ClearStatus();
            ApplyTexts();
        }

        bool EditSettings()
        {
            using (var dlg = new SettingsDialog(settings))
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return false;
                settings = dlg.Result;
            }
            ApplyTexts();
            return true;
        }

        void ChooseLocal()
        {
            if (localImage != null) { localImage = null; ApplyTexts(); return; }
            using (var dlg = new OpenFileDialog { Filter = "Ctrl-Z (*.iso)|*.iso", Title = L.T("Choisir une image", "Choose an image") })
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                localImage = dlg.FileName;
                string name = Path.GetFileName(localImage).ToLowerInvariant();
                if (name.Contains("business") || name.Contains("entreprise")) segEdition.Selected = 1;
                else if (name.Contains("personal") || name.Contains("particulier")) segEdition.Selected = 0;
                ApplyTexts();
            }
        }

        void Progress(string step, long done, long total)
        {
            if (IsDisposed) return;
            BeginInvoke((Action)delegate
            {
                progressStep = step; progressDone = done; progressTotal = total;
                Invalidate();
            });
        }

        /// <summary>
        /// Text of the future /etc/ctrl-z/config.env: the language for both
        /// editions, plus the business edition's settings.
        /// </summary>
        string BuildEnv(string edition)
        {
            string env = "# Ctrl-Z installer " + BuildInfo.Version + ", " + DateTime.Now.ToString("yyyy-MM-dd") + "\n"
                       + Imaging.EnvLine("RECOVERY_LANG", L.Lang);
            if (edition != "business") return env;
            return env
                + Imaging.EnvLine("RECOVERY_COMPANY", settings.Company)
                + Imaging.EnvLine("RECOVERY_KEY_ID", settings.KeyId)
                + Imaging.EnvLine("RECOVERY_GIT_URL", settings.GitUrl)
                + Imaging.EnvLine("RECOVERY_LOG_URL", settings.LogUrl)
                + Imaging.EnvLine("RECOVERY_LOG_TOKEN", settings.Token)
                + Imaging.EnvLine("RECOVERY_JOBS_DIR", "/mnt/jobs");
        }

        string EraseWarning(UsbDisk target, string edition)
        {
            string warning = L.T("Tout le contenu de ce disque sera définitivement effacé :", "Everything on this disk will be permanently erased:")
                           + "\n\n" + target + "\n\n";
            if (target.Size > BigDisk)
                warning += L.T("ATTENTION : ce disque est très grand pour une clé USB. Vérifiez qu'il ne s'agit pas d'un disque dur externe contenant vos sauvegardes.",
                               "WARNING: this disk is very large for a USB key. Check that it is not an external hard drive holding your backups.") + "\n\n";
            return warning + L.T("Écrire l'édition « " + EditionName(edition) + " » dessus ?", "Write the " + EditionName(edition) + " edition to it?");
        }

        async Task WriteKey()
        {
            UsbDisk target = disk;
            if (target == null) { ChooseDisk(); return; }
            string edition = Edition;
            if (edition == "business" && !settings.Complete && !EditSettings()) return;
            byte[] blob = Imaging.BuildBlob(BuildEnv(edition));

            if (!MessageDialog.Ask(this, L.T("Effacer cette clé ?", "Erase this key?"), EraseWarning(target, edition),
                    L.T("Effacer et écrire", "Erase and write"), L.T("Annuler", "Cancel"), true))
                return;

            progressStep = L.T("Préparation", "Preparing"); progressDone = progressTotal = 0;
            ClearStatus();
            SetView(View.Busy);
            try
            {
                string local = localImage;
                await Task.Run(delegate
                {
                    string image = local;
                    if (image == null)
                    {
                        Progress(L.T("Recherche de la dernière release", "Looking for the latest release"), 0, 0);
                        image = Releases.Download(Releases.Latest(edition), edition, Progress);
                    }
                    long length = new FileInfo(image).Length;
                    if (target.Size < Imaging.BlobOffset(length) + Imaging.BlobArea + 2048L * 1024 * 1024)
                    {
                        string need = UsbDisk.FormatSize(length + 2200L * 1024 * 1024);
                        throw new IOException(L.T("Cette clé est trop petite : il faut au moins " + need + " (image + espace de persistance).",
                                                  "This key is too small: at least " + need + " is needed (image + persistence space)."));
                    }

                    using (RawDisk raw = Disks.OpenForWrite(target))
                    {
                        string sha = Imaging.Write(image, raw.Stream, blob, delegate(long d, long t) { Progress(L.T("Écriture de la clé", "Writing the key"), d, t); });
                        raw.Stream.Flush(true);
                        if (!Imaging.Verify(raw.Stream, length, sha, blob, delegate(long d, long t) { Progress(L.T("Relecture de contrôle", "Verifying"), d, t); }))
                            throw new IOException(L.T("La relecture de la clé ne correspond pas à l'image. La clé est peut-être défectueuse : essayez-en une autre.",
                                                      "The key does not read back as the image. The key may be faulty: try another one."));
                    }
                });
                SetView(View.Done);
            }
            catch (Exception e)
            {
                status = L.T("Échec : ", "Failed: ") + e.Message;
                statusIsError = true;
                SetView(View.Setup);
                MessageDialog.Show(this, L.T("La clé n'a pas été créée", "The key was not created"), e.Message);
            }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (view == View.Busy)
            {
                e.Cancel = true;
                MessageDialog.Show(this, L.T("Écriture en cours", "Write in progress"),
                    L.T("Attendez la fin pour ne pas laisser la clé dans un état incomplet.",
                        "Wait for it to finish so the key is not left incomplete."));
            }
            base.OnFormClosing(e);
        }

        // --- Screenshots (--screenshot) ----------------------------------------------

        public static UsbDisk DemoDisk(long size)
        {
            return new UsbDisk { Number = 2, Model = "SanDisk Ultra USB 3.0", Size = size };
        }

        /// <summary>Puts the window in a given state, or returns the dialog to capture.</summary>
        public Form Demo(string state)
        {
            if (state == "disk" || state == "confirm") disk = DemoDisk(62L * 1000 * 1000 * 1000);
            if (state == "business" || state == "settings")
            {
                disk = DemoDisk(62L * 1000 * 1000 * 1000);
                segEdition.Selected = 1;
                settings = new KeySettings { Company = "Atelier Exemple", KeyId = "cle01", LogUrl = "https://logs.exemple.lan", Token = "0123456789abcdef" };
            }
            if (state == "busy")
            {
                disk = DemoDisk(62L * 1000 * 1000 * 1000);
                progressStep = L.T("Écriture de la clé", "Writing the key");
                progressDone = 612L * 1000 * 1000; progressTotal = 1416L * 1000 * 1000;
                view = View.Busy;
            }
            if (state == "done") { disk = DemoDisk(62L * 1000 * 1000 * 1000); view = View.Done; }
            ApplyTexts();
            if (state == "confirm")
                return new MessageDialog(L.T("Effacer cette clé ?", "Erase this key?"), EraseWarning(disk, Edition),
                    L.T("Effacer et écrire", "Erase and write"), L.T("Annuler", "Cancel"), ButtonKind.Danger);
            if (state == "settings") return new SettingsDialog(settings);
            if (state == "disks")
            {
                var list = new System.Collections.Generic.List<UsbDisk> { DemoDisk(62L * 1000 * 1000 * 1000),
                    new UsbDisk { Number = 3, Model = "Seagate Expansion HDD", Size = 2000L * 1000 * 1000 * 1000 } };
                return new DiskDialog { Demo = list };
            }
            return this;
        }
    }
}
