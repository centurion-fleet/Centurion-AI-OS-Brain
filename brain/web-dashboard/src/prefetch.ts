/** Prefetch the Mission chunk on pointerdown so open feels instant. */
export function prefetchMissionChunk() {
  void import("./screens/Mission");
}
