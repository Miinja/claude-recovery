// Langue de l'interface : francais ou anglais, au choix dans la fenetre.
using System.Globalization;

namespace ClaudeRecovery
{
    public static class L
    {
        /// <summary>"fr" ou "en". Par defaut, la langue de Windows.</summary>
        public static string Lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "fr" ? "fr" : "en";

        public static string T(string fr, string en)
        {
            return Lang == "fr" ? fr : en;
        }
    }
}
