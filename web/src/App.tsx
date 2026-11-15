/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { lazy, Suspense, useEffect } from "react";
import { CreateForm } from "@/components/CreateForm";
import { Selection } from "@/components/Selection";
import { SpawnPicker } from "@/components/SpawnPicker";
import { TitleCard } from "@/components/TitleCard";
import { cn } from "@/lib/cn";
import { isEnvBrowser, sendReady, sendSkip } from "@/lib/nui";
import { installMessages, useSceneStore } from "@/store/sceneStore";
import { Screen } from "@/types/protocol";

// Dev only: removed from production builds.
// Dev and showcase builds only: removed from production builds.
const Preview = import.meta.env.DEV || import.meta.env.MODE === "showcase" ? lazy(() => import("@/dev/Preview")) : null;

export default function App() {
  const screen = useSceneStore((state) => state.screen);
  const visible = useSceneStore((state) => state.visible);
  const skippable = useSceneStore((state) => state.config.skippable);
  const animations = useSceneStore((state) => state.config.layout.animations);

  useEffect(() => {
    const uninstall = installMessages();

    void sendReady();

    return uninstall;
  }, []);

  useEffect(() => {
    if (screen !== Screen.Intro || !skippable) {
      return undefined;
    }

    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Enter" || event.key === "Escape") {
        void sendSkip();
      }
    };

    window.addEventListener("keydown", onKey);

    return () => window.removeEventListener("keydown", onKey);
  }, [screen, skippable]);

  return (
    <div data-root className={cn(!animations && "ug-still")}>
      <TitleCard />
      <div className={cn("transition-opacity duration-500", visible ? "opacity-100" : "opacity-0")}>
        {screen === Screen.Select && <Selection />}
        {screen === Screen.Create && <CreateForm />}
        {screen === Screen.Spawn && <SpawnPicker />}
      </div>
      {Preview && isEnvBrowser() && (
        <Suspense fallback={null}>
          <Preview />
        </Suspense>
      )}
    </div>
  );
}
