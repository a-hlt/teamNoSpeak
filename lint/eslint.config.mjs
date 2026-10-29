// Configuration ESLint v9 (flat config) pour le frontend React
// On utilise le format ESM (.mjs) requis par ESLint 9
import js from "@eslint/js";
import globals from "globals";

export default [
  // Règles de base recommandées par ESLint
  js.configs.recommended,
  {
    files: ["**/*.js", "**/*.jsx"],
    languageOptions: {
      // Globales navigateur (window, document, fetch...) + ES2022
      globals: {
        ...globals.browser,
        ...globals.es2022,
      },
      ecmaVersion: 2022,
      sourceType: "module",
    },
    rules: {
      // Erreurs communes détectées statiquement
      "no-unused-vars": "warn",
      "no-undef": "error",
      "no-console": "warn",
      // Style
      "semi": ["error", "always"],
      "quotes": ["warn", "single"],
    },
  },
];
