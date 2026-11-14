// Fenetre de l'installeur : langue, edition, cle USB, reglages, ecriture.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace ClaudeRecovery
{
    public sealed class MainForm : Form
    {
        readonly Label lblTitle = new Label();
        readonly Label lblLang = new Label();
        readonly ComboBox cbLang = new ComboBox();
        readonly GroupBox gbEdition = new GroupBox();
        readonly RadioButton rbParticulier = new RadioButton();
        readonly RadioButton rbEntreprise = new RadioButton();
        readonly Label lblParticulier = new Label();
        readonly Label lblEntreprise = new Label();
        readonly Button btnLocal = new Button();
        readonly Label lblSource = new Label();
        readonly GroupBox gbDisk = new GroupBox();
        readonly ComboBox cbDisk = new ComboBox();
        readonly Button btnRefresh = new Button();
        readonly GroupBox gbSettings = new GroupBox();
        readonly TextBox tbCompany = new TextBox();
        readonly TextBox tbKeyId = new TextBox();
        readonly TextBox tbLogUrl = new TextBox();
        readonly TextBox tbLogToken = new TextBox();
        readonly TextBox tbGitUrl = new TextBox();
        readonly Label[] fieldLabels = new Label[5];
        readonly Label[] fieldHints = new Label[5];
        readonly ProgressBar bar = new ProgressBar();
        readonly Label lblStatus = new Label();
        readonly Button btnWrite = new Button();
        string localImage;
        bool busy;

        public MainForm()
        {
            Font = new Font("Segoe UI", 9f);
            AutoScaleMode = AutoScaleMode.Dpi;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(600, 640);

            lblTitle.Font = new Font("Segoe UI", 14f, FontStyle.Bold);
            lblTitle.Location = new Point(16, 12); lblTitle.AutoSize = true;
            lblLang.Location = new Point(388, 20); lblLang.Size = new Size(84, 18); lblLang.TextAlign = ContentAlignment.MiddleRight;
            cbLang.DropDownStyle = ComboBoxStyle.DropDownList; cbLang.Location = new Point(478, 17); cbLang.Size = new Size(106, 24);
            cbLang.Items.AddRange(new object[] { "Français", "English" });
            cbLang.SelectedIndex = L.Lang == "fr" ? 0 : 1;
            Controls.AddRange(new Control[] { lblTitle, lblLang, cbLang });

            // --- 1. Edition ---
            gbEdition.Location = new Point(16, 52); gbEdition.Size = new Size(568, 150);
            rbParticulier.Font = new Font(Font, FontStyle.Bold);
            rbParticulier.Location = new Point(14, 22); rbParticulier.AutoSize = true; rbParticulier.Checked = true;
            lblParticulier.Location = new Point(32, 44); lblParticulier.Size = new Size(524, 18); lblParticulier.ForeColor = SystemColors.GrayText;
            rbEntreprise.Font = new Font(Font, FontStyle.Bold);
            rbEntreprise.Location = new Point(14, 68); rbEntreprise.AutoSize = true;
            lblEntreprise.Location = new Point(32, 90); lblEntreprise.Size = new Size(524, 18); lblEntreprise.ForeColor = SystemColors.GrayText;
            btnLocal.Location = new Point(14, 114); btnLocal.Size = new Size(170, 26);
            lblSource.Location = new Point(192, 119); lblSource.Size = new Size(364, 18); lblSource.AutoEllipsis = true;
            gbEdition.Controls.AddRange(new Control[] { rbParticulier, lblParticulier, rbEntreprise, lblEntreprise, btnLocal, lblSource });
            Controls.Add(gbEdition);

            // --- 2. Cle USB ---
            gbDisk.Location = new Point(16, 210); gbDisk.Size = new Size(568, 62);
            cbDisk.DropDownStyle = ComboBoxStyle.DropDownList; cbDisk.Location = new Point(14, 24); cbDisk.Size = new Size(430, 24);
            btnRefresh.Location = new Point(454, 23); btnRefresh.Size = new Size(100, 26);
            gbDisk.Controls.AddRange(new Control[] { cbDisk, btnRefresh });
            Controls.Add(gbDisk);

            // --- 3. Reglages entreprise ---
            gbSettings.Location = new Point(16, 280); gbSettings.Size = new Size(568, 216);
            TextBox[] boxes = { tbCompany, tbKeyId, tbLogUrl, tbLogToken, tbGitUrl };
            for (int row = 0; row < boxes.Length; row++)
            {
                int y = 24 + row * 38;
                fieldLabels[row] = new Label { Location = new Point(14, y + 3), Size = new Size(140, 18) };
                boxes[row].Location = new Point(158, y); boxes[row].Size = new Size(396, 23);
                fieldHints[row] = new Label { Location = new Point(158, y + 22), Size = new Size(396, 14), ForeColor = SystemColors.GrayText, Font = new Font("Segoe UI", 7.5f) };
                gbSettings.Controls.AddRange(new Control[] { fieldLabels[row], boxes[row], fieldHints[row] });
            }
            tbLogToken.UseSystemPasswordChar = true;
            Controls.Add(gbSettings);

            // --- Ecriture ---
            bar.Location = new Point(16, 510); bar.Size = new Size(568, 20); bar.Maximum = 1000;
            lblStatus.Location = new Point(16, 536); lblStatus.Size = new Size(568, 40);
            btnWrite.Location = new Point(424, 588); btnWrite.Size = new Size(160, 36);
            btnWrite.Font = new Font(Font, FontStyle.Bold);
            Controls.AddRange(new Control[] { bar, lblStatus, btnWrite });

            cbLang.SelectedIndexChanged += delegate { L.Lang = cbLang.SelectedIndex == 0 ? "fr" : "en"; ApplyTexts(); RefreshDisks(); };
            rbEntreprise.CheckedChanged += delegate { ApplyTexts(); };
            btnRefresh.Click += delegate { RefreshDisks(); };
            btnLocal.Click += delegate { ChooseLocal(); };
            btnWrite.Click += async delegate { await WriteKey(); };
            Load += delegate { ApplyTexts(); RefreshDisks(); };
        }

        string Edition { get { return rbEntreprise.Checked ? "entreprise" : "particulier"; } }

        static string EditionName(string edition)
        {
            return edition == "entreprise" ? L.T("entreprise", "business") : L.T("particulier", "personal");
        }

        /// <summary>Pose tous les textes de la fenetre dans la langue courante.</summary>
        void ApplyTexts()
        {
            Text = L.T("Claude Recovery - Créer une clé", "Claude Recovery - Create a key") + " (" + BuildInfo.Version + ")";
            lblTitle.Text = L.T("Créer une clé Claude Recovery", "Create a Claude Recovery key");
            lblLang.Text = L.T("Langue", "Language");

            gbEdition.Text = L.T("1. Édition", "1. Edition");
            rbParticulier.Text = L.T("Particulier", "Personal");
            lblParticulier.Text = L.T("Pour récupérer ses propres fichiers. Claude explique chaque étape. Rien n'est envoyé à un serveur.",
                                      "To recover your own files. Claude explains every step. Nothing is sent to a server.");
            rbEntreprise.Text = L.T("Entreprise", "Business");
            lblEntreprise.Text = L.T("Pour un technicien. Chaque commande est journalisée et envoyée au serveur de l'entreprise.",
                                     "For a technician. Every command is logged and sent to the company's server.");
            btnLocal.Text = localImage != null ? L.T("Revenir à la release", "Back to the release") : L.T("Fichier image local…", "Local image file…");
            lblSource.Text = localImage != null
                ? Path.GetFileName(localImage)
                : L.T("Dernière release de github.com/", "Latest release of github.com/") + Releases.Repo;

            gbDisk.Text = L.T("2. Clé USB (elle sera entièrement effacée)", "2. USB key (it will be completely erased)");
            btnRefresh.Text = L.T("Actualiser", "Refresh");

            gbSettings.Text = L.T("3. Réglages de l'édition entreprise", "3. Business edition settings");
            gbSettings.Enabled = rbEntreprise.Checked && !busy;
            string[] labels = {
                L.T("Nom de l'entreprise", "Company name"),
                L.T("Nom de cette clé", "Name of this key"),
                L.T("Serveur de journaux", "Log server"),
                L.T("Jeton de la clé", "Key token"),
                L.T("Dépôt de mise à jour", "Update repository") };
            string[] hints = {
                "",
                L.T("ex. cle01 - apparaît dans les journaux", "e.g. key01 - shown in the logs"),
                L.T("https://… - vide : journal conservé sur la clé seulement", "https://… - empty: logs stay on the key only"),
                L.T("jeton de cette clé sur le serveur de journaux", "this key's token on the log server"),
                L.T("facultatif - vide : dépôt GitHub du projet", "optional - empty: the project's GitHub repository") };
            for (int i = 0; i < labels.Length; i++) { fieldLabels[i].Text = labels[i]; fieldHints[i].Text = hints[i]; }

            btnWrite.Text = L.T("Écrire la clé", "Write the key");
        }

        void RefreshDisks()
        {
            cbDisk.Items.Clear();
            foreach (UsbDisk d in Disks.ListUsb()) cbDisk.Items.Add(d);
            if (cbDisk.Items.Count > 0) cbDisk.SelectedIndex = 0;
            SetStatus(cbDisk.Items.Count == 0
                ? L.T("Aucune clé USB détectée. Branchez-en une, puis cliquez sur Actualiser.",
                      "No USB key detected. Plug one in, then click Refresh.")
                : "");
        }

        void ChooseLocal()
        {
            if (localImage != null) { localImage = null; ApplyTexts(); return; }
            using (var dlg = new OpenFileDialog { Filter = "Claude Recovery (*.iso)|*.iso", Title = L.T("Choisir une image", "Choose an image") })
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                localImage = dlg.FileName;
                string name = Path.GetFileName(localImage).ToLowerInvariant();
                if (name.Contains("entreprise")) rbEntreprise.Checked = true;
                else if (name.Contains("particulier")) rbParticulier.Checked = true;
                ApplyTexts();
            }
        }

        void SetStatus(string text) { lblStatus.Text = text; }

        void Progress(string step, long done, long total)
        {
            if (IsDisposed) return;
            BeginInvoke((Action)delegate
            {
                bar.Value = total > 0 ? (int)Math.Min(1000, done * 1000 / total) : 0;
                lblStatus.Text = total > 0 ? step + " - " + UsbDisk.FormatSize(done) + " / " + UsbDisk.FormatSize(total) : step;
            });
        }

        /// <summary>
        /// Texte du futur /etc/claude-recovery/config.env : la langue pour les deux editions,
        /// plus les reglages de l'edition entreprise. Null si ceux-ci sont invalides.
        /// </summary>
        string BuildEnv(string edition)
        {
            string env = "# Claude Recovery installer " + BuildInfo.Version + ", " + DateTime.Now.ToString("yyyy-MM-dd") + "\n"
                       + Imaging.EnvLine("RECOVERY_LANG", L.Lang);
            if (edition != "entreprise") return env;

            string company = tbCompany.Text.Trim(), key = tbKeyId.Text.Trim();
            string logUrl = tbLogUrl.Text.Trim(), token = tbLogToken.Text.Trim(), git = tbGitUrl.Text.Trim();
            string error = null;
            if (!Regex.IsMatch(key, "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"))
                error = L.T("Le nom de la clé est obligatoire : lettres, chiffres, point, tiret ou souligné (ex. cle01).",
                            "The key name is required: letters, digits, dot, dash or underscore (e.g. key01).");
            else if (logUrl.Length > 0 && !Regex.IsMatch(logUrl, "^https?://[^\\s]+$"))
                error = L.T("L'adresse du serveur de journaux doit commencer par https://",
                            "The log server address must start with https://");
            else if (logUrl.Length > 0 && token.Length == 0)
                error = L.T("Un serveur de journaux est indiqué : le jeton de la clé est obligatoire.",
                            "A log server is set: the key token is required.");
            else if (git.Length > 0 && !Regex.IsMatch(git, "^https?://[^\\s]+$"))
                error = L.T("L'adresse du dépôt de mise à jour doit commencer par https://",
                            "The update repository address must start with https://");
            if (error != null)
            {
                MessageBox.Show(this, error, L.T("Réglages incomplets", "Incomplete settings"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return null;
            }
            return env
                + Imaging.EnvLine("RECOVERY_COMPANY", company)
                + Imaging.EnvLine("RECOVERY_KEY_ID", key)
                + Imaging.EnvLine("RECOVERY_GIT_URL", git)
                + Imaging.EnvLine("RECOVERY_LOG_URL", logUrl)
                + Imaging.EnvLine("RECOVERY_LOG_TOKEN", token)
                + Imaging.EnvLine("RECOVERY_JOBS_DIR", "/mnt/jobs");
        }

        async Task WriteKey()
        {
            var disk = cbDisk.SelectedItem as UsbDisk;
            if (disk == null) { SetStatus(L.T("Choisissez d'abord une clé USB.", "Choose a USB key first.")); return; }
            string edition = Edition;
            string env = BuildEnv(edition);
            if (env == null) return;
            byte[] blob = Imaging.BuildBlob(env);

            string warning = L.T("Tout le contenu de ce disque sera définitivement effacé :", "Everything on this disk will be permanently erased:")
                           + "\n\n    " + disk + "\n\n";
            if (disk.Size > 130L * 1000 * 1000 * 1000)
                warning += L.T("ATTENTION : ce disque est très grand pour une clé USB. Vérifiez qu'il ne s'agit pas d'un disque dur externe contenant vos sauvegardes.",
                               "WARNING: this disk is very large for a USB key. Check that it is not an external hard drive holding your backups.") + "\n\n";
            warning += L.T("Écrire l'édition « " + EditionName(edition) + " » dessus ?", "Write the " + EditionName(edition) + " edition to it?");
            if (MessageBox.Show(this, warning, L.T("Confirmer l'effacement", "Confirm erasure"), MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
                return;

            SetBusy(true);
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
                    if (disk.Size < Imaging.BlobOffset(length) + Imaging.BlobArea + 2048L * 1024 * 1024)
                    {
                        string need = UsbDisk.FormatSize(length + 2200L * 1024 * 1024);
                        throw new IOException(L.T("Cette clé est trop petite : il faut au moins " + need + " (image + espace de persistance).",
                                                  "This key is too small: at least " + need + " is needed (image + persistence space)."));
                    }

                    using (RawDisk raw = Disks.OpenForWrite(disk))
                    {
                        string sha = Imaging.Write(image, raw.Stream, blob, delegate(long d, long t) { Progress(L.T("Écriture de la clé", "Writing the key"), d, t); });
                        raw.Stream.Flush(true);
                        if (!Imaging.Verify(raw.Stream, length, sha, blob, delegate(long d, long t) { Progress(L.T("Relecture de contrôle", "Verifying"), d, t); }))
                            throw new IOException(L.T("La relecture de la clé ne correspond pas à l'image. La clé est peut-être défectueuse : essayez-en une autre.",
                                                      "The key does not read back as the image. The key may be faulty: try another one."));
                    }
                });
                bar.Value = bar.Maximum;
                SetStatus(L.T("Clé prête.", "Key ready."));
                MessageBox.Show(this,
                    L.T("La clé est prête.\n\nDémarrez un PC dessus, puis tapez :  claude-recovery\n\nAu premier démarrage, la clé crée son espace de persistance et vous demande de vous connecter à votre compte Claude.",
                        "The key is ready.\n\nBoot a PC from it, then type:  claude-recovery\n\nOn first boot, the key creates its persistence space and asks you to sign in to your Claude account."),
                    L.T("Terminé", "Done"), MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception e)
            {
                bar.Value = 0;
                SetStatus(L.T("Échec : ", "Failed: ") + e.Message);
                MessageBox.Show(this, e.Message, L.T("La clé n'a pas été créée", "The key was not created"), MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                SetBusy(false);
                string status = lblStatus.Text;
                RefreshDisks();
                SetStatus(status);
            }
        }

        void SetBusy(bool value)
        {
            busy = value;
            gbEdition.Enabled = gbDisk.Enabled = btnWrite.Enabled = cbLang.Enabled = !value;
            gbSettings.Enabled = rbEntreprise.Checked && !value;
            UseWaitCursor = value;
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (busy)
            {
                e.Cancel = true;
                MessageBox.Show(this,
                    L.T("Une écriture est en cours. Attendez la fin pour ne pas laisser la clé dans un état incomplet.",
                        "A write is in progress. Wait for it to finish so the key is not left incomplete."),
                    L.T("Écriture en cours", "Write in progress"), MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            base.OnFormClosing(e);
        }
    }
}
