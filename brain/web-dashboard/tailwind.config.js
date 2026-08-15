/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        sans: ['"Instrument Sans"', "system-ui", "sans-serif"],
        display: ['"Instrument Serif"', "Georgia", "serif"],
      },
      colors: {
        background: "var(--canvas)",
        foreground: "var(--ink)",
        accent: {
          DEFAULT: "var(--accent)",
          bright: "var(--accent-bright)",
          soft: "var(--muted)",
          muted: "var(--accent-muted)",
        },
        border: "var(--border)",
        muted: "var(--muted)",
        surface: "var(--surface)",
        card: "var(--card)",
        canvas: "var(--canvas)",
        /* amber-* kept as aliases so existing classNames pick up bronze. */
        amber: {
          glow: "var(--accent)",
          bright: "var(--accent-bright)",
          soft: "var(--muted)",
          muted: "var(--accent-muted)",
        },
        glass: {
          DEFAULT: "var(--glass)",
          border: "var(--border)",
          hover: "var(--glass-hover)",
        },
        ink: {
          DEFAULT: "var(--ink)",
          muted: "var(--muted)",
          dim: "var(--muted)",
        },
      },
      boxShadow: {
        amber: "none",
        "amber-sm": "none",
        glass: "0 8px 32px rgba(0, 0, 0, 0.28)",
      },
      backgroundImage: {
        "amber-gradient": "linear-gradient(90deg, var(--accent), var(--accent))",
        horizon: "none",
      },
      animation: {
        "pulse-soft": "pulse-soft 3s ease-in-out infinite",
      },
      keyframes: {
        "pulse-soft": {
          "0%, 100%": { opacity: "0.6" },
          "50%": { opacity: "1" },
        },
      },
    },
  },
  plugins: [],
};
