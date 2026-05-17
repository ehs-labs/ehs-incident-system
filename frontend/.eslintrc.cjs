module.exports = {
  root: true,
  env: { browser: true, node: true, es2022: true },
  extends: [
    "eslint:recommended",
    "plugin:vue/vue3-recommended",
    "plugin:@typescript-eslint/recommended"
  ],
  parser: "vue-eslint-parser",
  parserOptions: {
    parser: "@typescript-eslint/parser",
    sourceType: "module",
    ecmaVersion: 2022
  },
  rules: {
    "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
    "vue/multi-word-component-names": "off"
  },
  ignorePatterns: ["dist/**", "node_modules/**", "src/api/generated/**"]
};
