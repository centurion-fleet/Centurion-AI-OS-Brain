import { Suspense, lazy } from "react";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { LazyMotion, domAnimation } from "framer-motion";
import { Deck } from "./screens/Deck";
import { AttentionFollow } from "./components/AttentionFollow";
import { embedDeckRole } from "./hooks/useDeckVisible";

const Mission = lazy(() =>
  import("./screens/Mission").then((m) => ({ default: m.Mission })),
);
const TV = lazy(() => import("./screens/TV").then((m) => ({ default: m.TV })));
const Discovery = lazy(() =>
  import("./screens/Discovery").then((m) => ({ default: m.Discovery })),
);
const Collab = lazy(() =>
  import("./screens/Collab").then((m) => ({ default: m.Collab })),
);

function RouteFallback() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-canvas text-ink-dim">
      Opening…
    </div>
  );
}

export default function App() {
  const role = embedDeckRole();
  // Brain Collab WebView must never mount Focus routes — AttentionFollow
  // resets the Focus tab to the homepage (decisions list).
  if (role === "collab") {
    return (
      <LazyMotion features={domAnimation} strict>
        <Suspense fallback={<RouteFallback />}>
          <Collab />
        </Suspense>
      </LazyMotion>
    );
  }

  return (
    <LazyMotion features={domAnimation} strict>
      <BrowserRouter>
        <AttentionFollow />
        <Suspense fallback={<RouteFallback />}>
          <Routes>
            <Route path="/" element={<Deck />} />
            <Route path="/mission/:id" element={<Mission />} />
            <Route path="/tv" element={<TV />} />
            <Route path="/discovery" element={<Discovery />} />
            <Route path="/collab" element={<Collab />} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Routes>
        </Suspense>
      </BrowserRouter>
    </LazyMotion>
  );
}
