import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { Deck } from "./screens/Deck";
import { Mission } from "./screens/Mission";
import { TV } from "./screens/TV";
import { Discovery } from "./screens/Discovery";

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Deck />} />
        <Route path="/mission/:id" element={<Mission />} />
        <Route path="/tv" element={<TV />} />
        <Route path="/discovery" element={<Discovery />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
