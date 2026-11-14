// Fenetre de l'installeur : edition, cle USB, reglages, ecriture.
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
        readonly RadioButton rbEntreprise = new RadioButton();
        readonly RadioButton rbParticulier = new RadioButton();
        readonly Button btnLocal = new Button();
        readonly Label lblSource = new Label();
        readonly ComboBox cbDisk = new ComboBox();
        readonly Button btnRefresh = new Button();
        readonly GroupBox gbSettings = new GroupBox();
        readonly TextBox tbCompany = new TextBox();
        readonly TextBox tbKeyId = new TextBox();
        readonly TextBox tbLogUrl = new TextBox();
        readonly TextBox tbLogToken = new TextBox();
        readonly TextBox tbGitUrl = new TextBox();
        readonly ProgressBar bar = new ProgressBar();
        readonly Label lblStatus = new Label();
        readonly Button btnWrite = new Button();
        string localImage;

        public MainForm()
        {
            Text = "Claude Recovery - Créer une clé (" + BuildInfo.Version + ")";
            Font = new Font("Segoe UI", 9f);
            AutoScaleMode = AutoScaleMode.Dpi;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(600, 640);

            var title = new Label { Text = "Créer une clé Claude Recovery", Font = new Font("Segoe UI", 14f, FontStyle.Bold), Location = new Point(16, 12), AutoSize = true };
            Controls.Add(title);

            // --- 1. Edition ---
            var gbEdition = new GroupBox { Text = "1. Édition", Location = new Point(16, 52), Size = new Size(568, 150) };
            rbParticulier.Text = "Particulier";
            rbParticulier.Font = new Font(Font, FontStyle.Bold);
            rbParticulier.Location = new Point(14, 22); rbParticulier.AutoSize = true; rbParticulier.Checked = true;
            var d1 = new Label { Text = "Pour récupérer ses propres fichiers. Claude explique chaque étape. Rien n'est envoyé à un serveur.", Location = new Point(32, 44), Size = new Size(520, 18), ForeColor = SystemColors.GrayText };
            rbEntreprise.Text = "Entreprise";
            rbEntreprise.Font = new Font(Font, FontStyle.Bold);
            rbEntreprise.Location = new Point(14, 68); rbEntreprise.AutoSize = true;
            var d2 = new Label { Text = "Pour un technicien. Chaque commande est journalisée et envoyée au serveur de l'entreprise.", Location = new Point(32, 90), Size = new Size(520, 18), ForeColor = SystemColors.GrayText };
            btnLocal.Text = "Fichier image local…"; btnLocal.Location = new Point(14, 114); btnLocal.Size = new Size(150, 26);
            lblSource.Location = new Point(172, 119); lblSource.Size = new Size(384, 18); lblSource.AutoEllipsis = true;
            gbEdition.Controls.AddRange(new Control[] { rbParticulier, d1, rbEntreprise, d2, btnLocal, lblSource });
            Controls.Add(gbEdition);

            // --- 2. Cle USB ---
            var gbDisk = new GroupBox { Text = "2. Clé USB (elle sera entièrement effacée)", Location = new Point(16, 210), Size = new Size(568, 62) };
            cbDisk.DropDownStyle = ComboBoxStyle.DropDownList; cbDisk.Location = new Point(14, 24); cbDisk.Size = new Size(430, 24);
            btnRefresh.Text = "Actualiser"; btnRefresh.Location = new Point(454, 23); btnRefresh.Size = new Size(100, 26);
            gbDisk.Controls.AddRange(new Control[] { cbDisk, btnRefresh });
            Controls.Add(gbDisk);

            // --- 3. Reglages entreprise ---
            gbSettings.Text = "3. Réglages de l'édition entreprise";
            gbSettings.Location = new Point(16, 280); gbSettings.Size = new Size(568, 216);
            AddField(gbSettings, 0, "Nom de l'entreprise", tbCompany, "");
            AddField(gbSettings, 1, "Nom de cette clé", tbKeyId, "ex. cle01 - apparaît dans les journaux");
            AddField(gbSettings, 2, "Serveur de journaux", tbLogUrl, "https://… - vide : journal conservé sur la clé seulement");
            AddField(gbSettings, 3, "Jeton de la clé", tbLogToken, "jeton de cette clé sur le serveur de journaux");
            AddField(gbSettings, 4, "Dépôt de mise à jour", tbGitUrl, "facultatif - vide : dépôt GitHub du projet");
            tbLogToken.UseSystemPasswordChar = true;
            Controls.Add(gbSettings);

            // --- Ecriture ---
            bar.Location = new Point(16, 510); bar.Size = new Size(568, 20); bar.Maximum = 1000;
            lblStatus.Location = new Point(16, 536); lblStatus.Size = new Size(568, 40);
            btnWrite.Text = "Écrire la clé"; btnWrite.Location = new Point(424, 588); btnWrite.Size = new Size(160, 36);
            btnWrite.Font = new Font(Font, FontStyle.Bold);
            Controls.AddRange(new Control[] { bar, lblStatus, btnWrite });

            rbEntreprise.CheckedChanged += delegate { UpdateState(); };
            btnRefresh.Click += delegate { RefreshDisks(); };
            btnLocal.Click += delegate { ChooseLocal(); };
            btnWrite.Click += async delegate { await WriteKey(); };
            Load += delegate { RefreshDisks(); UpdateState(); };
        }

        static void AddField(GroupBox box, int row, string label, TextBox tb, string hint)
        {
            int y = 24 + row * 38;
            box.Controls.Add(new Label { Text = label, Location = new Point(14, y + 3), Size = new Size(140, 18) });
            tb.Location = new Point(158, y); tb.Size = new Size(396, 23);
            box.Controls.Add(tb);
            box.Controls.Add(new Label { Text = hint, Location = new Point(158, y + 22), Size = new Size(396, 14), ForeColor = SystemColors.GrayText, Font = new Font("Segoe UI", 7.5f) });
        }

        string Edition { get { return rbEntreprise.Checked ? "entreprise" : "particulier"; } }

        void UpdateState()
        {
            gbSettings.Enabled = rbEntreprise.Checked;
            lblSource.Text = localImage != null
                ? Path.GetFileName(localImage)
                : "Dernière release de github.com/" + Releases.Repo;
        }

        void RefreshDisks()
        {
            cbDisk.Items.Clear();
            foreach (UsbDisk d in Disks.ListUsb()) cbDisk.Items.Add(d);
            if (cbDisk.Items.Count > 0) cbDisk.SelectedIndex = 0;
            SetStatus(cbDisk.Items.Count == 0 ? "Aucune clé USB détectée. Branchez-en une, puis cliquez sur Actualiser." : "");
        }

        void ChooseLocal()
        {
            if (localImage != null) { localImage = null; btnLocal.Text = "Fichier image local…"; UpdateState(); return; }
            using (var dlg = new OpenFileDialog { Filter = "Image Claude Recovery (*.iso)|*.iso", Title = "Choisir une image" })
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;
                localImage = dlg.FileName;
                string name = Path.GetFileName(localImage).ToLowerInvariant();
                if (name.Contains("entreprise")) rbEntreprise.Checked = true;
                else if (name.Contains("particulier")) rbParticulier.Checked = true;
                btnLocal.Text = "Revenir à la release";
                UpdateState();
            }
        }

        void SetStatus(string text) { lblStatus.Text = text; }

        void Progress(string step, long done, long total)
        {
            if (IsDisposed) return;
            BeginInvoke((Action)delegate
            {
                bar.Value = total > 0 ? (int)Math.Min(1000, done * 1000 / total) : 0;
                lblStatus.Text = step + " - " + UsbDisk.FormatSize(done) + " / " + UsbDisk.FormatSize(total);
            });
        }

        /// <summary>Texte de /etc/ordi/ordi.env, ou null si les reglages sont invalides.</summary>
        string BuildEnv()
        {
            string company = tbCompany.Text.Trim(), key = tbKeyId.Text.Trim();
            string logUrl = tbLogUrl.Text.Trim(), token = tbLogToken.Text.Trim(), git = tbGitUrl.Text.Trim();
            string error = null;
            if (!Regex.IsMatch(key, "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"))
                error = "Le nom de la clé est obligatoire : lettres, chiffres, point, tiret ou souligné (ex. cle01).";
            else if (logUrl.Length > 0 && !Regex.IsMatch(logUrl, "^https?://[^\\s]+$"))
                error = "L'adresse du serveur de journaux doit commencer par https://";
            else if (logUrl.Length > 0 && token.Length == 0)
                error = "Un serveur de journaux est indiqué : le jeton de la clé est obligatoire.";
            else if (git.Length > 0 && !Regex.IsMatch(git, "^https?://[^\\s]+$"))
                error = "L'adresse du dépôt de mise à jour doit commencer par https://";
            if (error != null)
            {
                MessageBox.Show(this, error, "Réglages incomplets", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return null;
            }
            return "# Ecrit par l'installeur Claude Recovery " + BuildInfo.Version + " le " + DateTime.Now.ToString("yyyy-MM-dd") + "\n"
                + Imaging.EnvLine("ORDI_COMPANY", company)
                + Imaging.EnvLine("ORDI_KEY_ID", key)
                + Imaging.EnvLine("ORDI_GIT_URL", git)
                + Imaging.EnvLine("ORDI_LOG_URL", logUrl)
                + Imaging.EnvLine("ORDI_LOG_TOKEN", token)
                + Imaging.EnvLine("ORDI_JOBS_DIR", "/mnt/jobs");
        }

        async Task WriteKey()
        {
            var disk = cbDisk.SelectedItem as UsbDisk;
            if (disk == null) { SetStatus("Choisissez d'abord une clé USB."); return; }
            string edition = Edition;
            byte[] blob = null;
            if (edition == "entreprise")
            {
                string env = BuildEnv();
                if (env == null) return;
                blob = Imaging.BuildBlob(env);
            }

            string warning = "Tout le contenu de ce disque sera définitivement effacé :\n\n    " + disk + "\n\n";
            if (disk.Size > 130L * 1000 * 1000 * 1000)
                warning += "ATTENTION : ce disque est très grand pour une clé USB. Vérifiez qu'il ne s'agit pas d'un disque dur externe contenant vos sauvegardes.\n\n";
            warning += "Écrire l'édition « " + edition + " » dessus ?";
            if (MessageBox.Show(this, warning, "Confirmer l'effacement", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
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
                        Progress("Recherche de la dernière release", 0, 0);
                        image = Releases.Download(Releases.Latest(edition), edition, Progress);
                    }
                    long length = new FileInfo(image).Length;
                    if (disk.Size < Imaging.BlobOffset(length) + Imaging.BlobArea + 2048L * 1024 * 1024)
                        throw new IOException("Cette clé est trop petite : il faut au moins "
                            + UsbDisk.FormatSize(length + 2200L * 1024 * 1024) + " (image + espace de persistance).");

                    using (RawDisk raw = Disks.OpenForWrite(disk))
                    {
                        string sha = Imaging.Write(image, raw.Stream, blob, delegate(long d, long t) { Progress("Écriture de la clé", d, t); });
                        raw.Stream.Flush(true);
                        if (!Imaging.Verify(raw.Stream, length, sha, blob, delegate(long d, long t) { Progress("Relecture de contrôle", d, t); }))
                            throw new IOException("La relecture de la clé ne correspond pas à l'image. La clé est peut-être défectueuse : essayez-en une autre.");
                    }
                });
                bar.Value = bar.Maximum;
                SetStatus("Clé prête.");
                MessageBox.Show(this,
                    "La clé est prête.\n\nDémarrez un PC dessus, puis tapez :  ordi\n\nAu premier démarrage, la clé crée son espace de persistance et vous demande de vous connecter à votre compte Claude.",
                    "Terminé", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception e)
            {
                bar.Value = 0;
                SetStatus("Échec : " + e.Message);
                MessageBox.Show(this, e.Message, "La clé n'a pas été créée", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
            finally
            {
                SetBusy(false);
                RefreshDisksQuiet();
            }
        }

        void RefreshDisksQuiet()
        {
            string status = lblStatus.Text;
            RefreshDisks();
            SetStatus(status);
        }

        void SetBusy(bool busy)
        {
            foreach (Control c in Controls)
                if (c is GroupBox || c == btnWrite) c.Enabled = !busy;
            if (!busy) UpdateState();
            UseWaitCursor = busy;
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (UseWaitCursor)
            {
                e.Cancel = true;
                MessageBox.Show(this, "Une écriture est en cours. Attendez la fin pour ne pas laisser la clé dans un état incomplet.", "Écriture en cours", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            base.OnFormClosing(e);
        }
    }
}
