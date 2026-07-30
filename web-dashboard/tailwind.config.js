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
        canvas: "#1a1410",
        surface: "#221c17",
        amber: {
          glow: "#ff9f1c",
          bright: "#ffd700",
          soft: "#ffb347",
          muted: "rgba(255, 159, 28, 0.15)",
        },
        glass: {
          DEFAULT: "rgba(255, 255, 255, 0.03)",
          border: "rgba(255, 255, 255, 0.08)",
          hover: "rgba(255, 255, 255, 0.06)",
        },
        ink: {
          DEFAULT: "#f5efe6",
          muted: "rgba(245, 239, 230, 0.55)",
          dim: "rgba(245, 239, 230, 0.35)",
        },
      },
      boxShadow: {
        amber: "0 0 40px rgba(255, 159, 28, 0.25)",
        "amber-sm": "0 0 20px rgba(255, 159, 28, 0.2)",
        glass: "0 8px 32px rgba(0, 0, 0, 0.35)",
      },
      backgroundImage: {
        "amber-gradient": "linear-gradient(90deg, #ff9f1c, #ffd700)",
        "horizon":
          "radial-gradient(ellipse 80% 50% at 50% -20%, rgba(255, 159, 28, 0.18), transparent), radial-gradient(ellipse 60% 40% at 100% 100%, rgba(255, 215, 0, 0.06), transparent)",
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
