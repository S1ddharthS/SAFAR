import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: "class",
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        paper: "rgb(var(--paper) / <alpha-value>)",
        surface: "rgb(var(--surface) / <alpha-value>)",
        raised: "rgb(var(--raised) / <alpha-value>)",
        ink: "rgb(var(--ink) / <alpha-value>)",
        muted: "rgb(var(--muted) / <alpha-value>)",
        faint: "rgb(var(--faint) / <alpha-value>)",
        line: "rgb(var(--line) / <alpha-value>)",
        ember: "rgb(var(--ember) / <alpha-value>)",
        "ember-soft": "rgb(var(--ember-soft) / <alpha-value>)",
        jade: "rgb(var(--jade) / <alpha-value>)",
        "jade-soft": "rgb(var(--jade-soft) / <alpha-value>)",
        rose: "rgb(var(--rose) / <alpha-value>)",
      },
      fontFamily: {
        display: ["var(--font-display)"],
        sans: ["var(--font-sans)"],
        mono: ["var(--font-mono)"],
      },
      letterSpacing: {
        editorial: "0.14em",
      },
      maxWidth: {
        prose: "68ch",
        wide: "82rem",
      },
      boxShadow: {
        card: "0 1px 0 rgb(var(--line) / 0.55), 0 10px 30px -24px rgb(var(--shadow) / 0.45)",
        lift: "0 30px 70px -38px rgb(var(--shadow) / 0.55)",
        float: "0 18px 50px -30px rgb(var(--shadow) / 0.5)",
      },
      borderRadius: {
        "4xl": "2rem",
      },
      transitionTimingFunction: {
        editorial: "cubic-bezier(0.22, 1, 0.36, 1)",
      },
      spacing: {
        "18": "4.5rem",
      },
      keyframes: {
        shimmer: {
          "0%": { backgroundPosition: "-400px 0" },
          "100%": { backgroundPosition: "400px 0" },
        },
      },
      animation: {
        shimmer: "shimmer 1.6s linear infinite",
      },
    },
  },
  plugins: [],
};

export default config;
