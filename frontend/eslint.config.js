import vuePlugin from "eslint-plugin-vue";
import tsPlugin from "@typescript-eslint/eslint-plugin";
import tsParser from "@typescript-eslint/parser";
import vueParser from "vue-eslint-parser";

export default [
  // Global ignores — replaces ignorePatterns in .eslintrc.cjs plus generated files
  {
    ignores: [
      "dist/**",
      "node_modules/**",
      "coverage/**",
      "playwright-report/**",
      "test-results/**",
      "src/api/schema.ts", // codegen output — do not lint
      "src/api/generated/**",
    ],
  },

  // eslint:recommended equivalent globals for browser + node + es2022
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: {
        // browser globals
        window: "readonly",
        document: "readonly",
        navigator: "readonly",
        console: "readonly",
        fetch: "readonly",
        setTimeout: "readonly",
        clearTimeout: "readonly",
        setInterval: "readonly",
        clearInterval: "readonly",
        URL: "readonly",
        URLSearchParams: "readonly",
        Request: "readonly",
        Response: "readonly",
        Headers: "readonly",
        FormData: "readonly",
        Blob: "readonly",
        File: "readonly",
        FileReader: "readonly",
        Event: "readonly",
        CustomEvent: "readonly",
        HTMLElement: "readonly",
        HTMLInputElement: "readonly",
        HTMLSelectElement: "readonly",
        HTMLTextAreaElement: "readonly",
        HTMLFormElement: "readonly",
        MouseEvent: "readonly",
        KeyboardEvent: "readonly",
        localStorage: "readonly",
        sessionStorage: "readonly",
        location: "readonly",
        history: "readonly",
        alert: "readonly",
        confirm: "readonly",
        // node globals
        process: "readonly",
        __dirname: "readonly",
        __filename: "readonly",
        Buffer: "readonly",
        global: "readonly",
        module: "readonly",
        require: "readonly",
        exports: "readonly",
      },
    },
  },

  // Vue flat/recommended — covers *.vue parsing with vue-eslint-parser
  ...vuePlugin.configs["flat/recommended"],

  // TypeScript flat/recommended — covers *.ts files
  ...tsPlugin.configs["flat/recommended"],

  // Project-wide overrides applied to all linted files
  {
    files: ["**/*.ts", "**/*.vue", "**/*.js"],
    plugins: {
      "@typescript-eslint": tsPlugin,
      vue: vuePlugin,
    },
    rules: {
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
      "vue/multi-word-component-names": "off",
    },
  },

  // Vue SFC files: use vue-eslint-parser with TS parser for <script>
  {
    files: ["**/*.vue"],
    languageOptions: {
      parser: vueParser,
      parserOptions: {
        parser: tsParser,
        sourceType: "module",
        ecmaVersion: 2022,
      },
    },
  },

  // Pure TypeScript files
  {
    files: ["**/*.ts"],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        sourceType: "module",
        ecmaVersion: 2022,
      },
    },
  },
];
