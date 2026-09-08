// Reference list for the Mother Language autocomplete (Settings). One
// representative country flag per language — languages don't inherently have
// flags, so this is a common-practice visual shortcut, not a claim about
// where a language "belongs". Kept pre-sorted A-Z by name so filtering never
// needs a separate sort step.
const LANGUAGES = [
  { name: 'Afrikaans', flag: '🇿🇦' },
  { name: 'Albanian', flag: '🇦🇱' },
  { name: 'Amharic', flag: '🇪🇹' },
  { name: 'Arabic', flag: '🇸🇦' },
  { name: 'Armenian', flag: '🇦🇲' },
  { name: 'Azerbaijani', flag: '🇦🇿' },
  { name: 'Basque', flag: '🇪🇸' },
  { name: 'Belarusian', flag: '🇧🇾' },
  { name: 'Bengali', flag: '🇧🇩' },
  { name: 'Bosnian', flag: '🇧🇦' },
  { name: 'Bulgarian', flag: '🇧🇬' },
  { name: 'Burmese', flag: '🇲🇲' },
  { name: 'Catalan', flag: '🇪🇸' },
  { name: 'Cebuano', flag: '🇵🇭' },
  { name: 'Chinese (Simplified)', flag: '🇨🇳' },
  { name: 'Chinese (Traditional)', flag: '🇹🇼' },
  { name: 'Croatian', flag: '🇭🇷' },
  { name: 'Czech', flag: '🇨🇿' },
  { name: 'Danish', flag: '🇩🇰' },
  { name: 'Dutch', flag: '🇳🇱' },
  { name: 'English', flag: '🇬🇧' },
  { name: 'Estonian', flag: '🇪🇪' },
  { name: 'Filipino', flag: '🇵🇭' },
  { name: 'Finnish', flag: '🇫🇮' },
  { name: 'French', flag: '🇫🇷' },
  { name: 'Georgian', flag: '🇬🇪' },
  { name: 'German', flag: '🇩🇪' },
  { name: 'Greek', flag: '🇬🇷' },
  { name: 'Gujarati', flag: '🇮🇳' },
  { name: 'Hausa', flag: '🇳🇬' },
  { name: 'Hebrew', flag: '🇮🇱' },
  { name: 'Hindi', flag: '🇮🇳' },
  { name: 'Hungarian', flag: '🇭🇺' },
  { name: 'Icelandic', flag: '🇮🇸' },
  { name: 'Indonesian', flag: '🇮🇩' },
  { name: 'Irish', flag: '🇮🇪' },
  { name: 'Italian', flag: '🇮🇹' },
  { name: 'Japanese', flag: '🇯🇵' },
  { name: 'Javanese', flag: '🇮🇩' },
  { name: 'Kannada', flag: '🇮🇳' },
  { name: 'Kazakh', flag: '🇰🇿' },
  { name: 'Khmer', flag: '🇰🇭' },
  { name: 'Korean', flag: '🇰🇷' },
  { name: 'Lao', flag: '🇱🇦' },
  { name: 'Latvian', flag: '🇱🇻' },
  { name: 'Lithuanian', flag: '🇱🇹' },
  { name: 'Macedonian', flag: '🇲🇰' },
  { name: 'Malay', flag: '🇲🇾' },
  { name: 'Malayalam', flag: '🇮🇳' },
  { name: 'Marathi', flag: '🇮🇳' },
  { name: 'Mongolian', flag: '🇲🇳' },
  { name: 'Nepali', flag: '🇳🇵' },
  { name: 'Norwegian', flag: '🇳🇴' },
  { name: 'Persian (Farsi)', flag: '🇮🇷' },
  { name: 'Polish', flag: '🇵🇱' },
  { name: 'Portuguese', flag: '🇵🇹' },
  { name: 'Punjabi', flag: '🇮🇳' },
  { name: 'Romanian', flag: '🇷🇴' },
  { name: 'Russian', flag: '🇷🇺' },
  { name: 'Serbian', flag: '🇷🇸' },
  { name: 'Sinhala', flag: '🇱🇰' },
  { name: 'Slovak', flag: '🇸🇰' },
  { name: 'Slovenian', flag: '🇸🇮' },
  { name: 'Spanish', flag: '🇪🇸' },
  { name: 'Swahili', flag: '🇰🇪' },
  { name: 'Swedish', flag: '🇸🇪' },
  { name: 'Tamil', flag: '🇮🇳' },
  { name: 'Telugu', flag: '🇮🇳' },
  { name: 'Thai', flag: '🇹🇭' },
  { name: 'Turkish', flag: '🇹🇷' },
  { name: 'Ukrainian', flag: '🇺🇦' },
  { name: 'Urdu', flag: '🇵🇰' },
  { name: 'Uzbek', flag: '🇺🇿' },
  { name: 'Vietnamese', flag: '🇻🇳' },
  { name: 'Welsh', flag: '🇬🇧' },
  { name: 'Zulu', flag: '🇿🇦' }
];

// Substring match (not just prefix) so e.g. "ese" still finds "Chinese",
// "Japanese", "Vietnamese" — results stay A-Z since LANGUAGES already is.
function findLanguages(query, limit) {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  const matches = LANGUAGES.filter((l) => l.name.toLowerCase().includes(q));
  return typeof limit === 'number' ? matches.slice(0, limit) : matches;
}

if (typeof window !== 'undefined') {
  window.Languages = { LANGUAGES, findLanguages };
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { LANGUAGES, findLanguages };
}
