/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { cn } from "@/lib/cn";
import { useSceneStore } from "@/store/sceneStore";
import { Screen } from "@/types/protocol";

/** The intro's title, like an opening credit: wide letters that breathe in and out. */
export function TitleCard() {
  const title = useSceneStore((state) => state.title);
  const screen = useSceneStore((state) => state.screen);
  const skipLabel = useSceneStore((state) => state.config.labels.skip);
  const skippable = useSceneStore((state) => state.config.skippable);

  return (
    <div className="pointer-events-none fixed inset-0 flex flex-col items-center justify-center">
      <h1
        className={cn(
          "px-8 text-center text-5xl font-light uppercase tracking-[0.5em] text-white drop-shadow-[0_2px_12px_rgba(0,0,0,0.8)] transition-all duration-[1600ms] ease-out",
          title.visible ? "translate-y-0 opacity-100 blur-0" : "translate-y-2 opacity-0 blur-sm",
        )}
      >
        {title.text}
      </h1>
      {screen === Screen.Intro && skippable && (
        <p className="absolute bottom-[16%] text-xs uppercase tracking-[0.3em] text-white/50 animate-ug-fade-in">{skipLabel}</p>
      )}
    </div>
  );
}
