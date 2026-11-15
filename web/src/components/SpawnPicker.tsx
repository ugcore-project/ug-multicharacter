/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useEffect } from "react";
import { ArrowLeft, History, MapPin, Navigation } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { Surface } from "@/components/ui/Surface";
import { Text } from "@/components/ui/Text";
import { cn } from "@/lib/cn";
import { BRAND_BAR, BRAND_FILL, toneAt } from "@/lib/tones";
import { sendCancel, sendSpawnChoose, sendSpawnHover } from "@/lib/nui";
import { useSceneStore } from "@/store/sceneStore";

const LAST = "last";

/** Where the character arrives. The camera flies over the hovered place behind the list. */
export function SpawnPicker() {
  const options = useSceneStore((state) => state.spawns);
  const focus = useSceneStore((state) => state.spawnFocus);
  const labels = useSceneStore((state) => state.config.labels);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const { spawns, spawnFocus, config } = useSceneStore.getState();

      if (!config.layout.keyboard && event.key !== "Escape") {
        return;
      }

      const index = spawns.findIndex((option) => option.id === spawnFocus);

      if (event.key === "ArrowUp" || event.key === "ArrowDown") {
        const step = event.key === "ArrowUp" ? -1 : 1;
        const next = spawns[(index + step + spawns.length) % spawns.length];

        if (next) {
          useSceneStore.setState({ spawnFocus: next.id });
          void sendSpawnHover(next.id);
        }
      } else if (event.key === "Enter" && spawnFocus) {
        void sendSpawnChoose(spawnFocus);
      } else if (event.key === "Escape") {
        void sendCancel();
      }
    };

    window.addEventListener("keydown", onKey);

    return () => window.removeEventListener("keydown", onKey);
  }, []);

  return (
    <div className="pointer-events-none fixed inset-0">
      <div className="absolute right-16 top-1/2 -translate-y-1/2">
        <Surface variant="glass" padding="none" className="pointer-events-auto w-80 overflow-hidden animate-ug-slide-up">
          <div className={BRAND_BAR} />
          <div className="flex flex-col gap-4 p-6">
            <h2 className="text-3xl font-semibold text-foreground">{labels.spawnTitle}</h2>
            <div role="listbox" aria-label={labels.spawnTitle} className="flex flex-col gap-2">
              {options.map((option, index) => {
                const active = option.id === focus;
                const tone = toneAt(index);
                const Icon = option.id === LAST ? History : MapPin;

                return (
                  <button
                    key={option.id}
                    type="button"
                    role="option"
                    aria-selected={active}
                    onMouseEnter={() => {
                      if (!active) {
                        useSceneStore.setState({ spawnFocus: option.id });
                        void sendSpawnHover(option.id);
                      }
                    }}
                    onClick={() => void sendSpawnChoose(option.id)}
                    className={cn(
                      "flex items-center gap-3 rounded-lg border px-3 py-3 text-left transition-all duration-300",
                      active ? cn("translate-x-1 bg-card/95 shadow-ug-md", tone.border) : "border-white/10 bg-card/60 hover:bg-card/80",
                    )}
                  >
                    <span className={cn("flex h-8 w-8 shrink-0 items-center justify-center rounded-lg", tone.chip, !active && "opacity-70")}>
                      <Icon size={18} aria-hidden="true" />
                    </span>
                    <span className="min-w-0">
                      <span className="block truncate text-sm font-medium text-foreground">{option.label}</span>
                      {option.street && <span className="block truncate text-xs text-muted-foreground">{option.street}</span>}
                    </span>
                  </button>
                );
              })}
            </div>
            <div className="flex gap-2">
              <Button type="button" variant="outline" className="h-11" onClick={() => void sendCancel()}>
                <ArrowLeft size={16} aria-hidden="true" />
                {labels.back}
              </Button>
              <Button type="button" className={cn("h-11 flex-1 text-base", BRAND_FILL)} disabled={!focus} onClick={() => focus && void sendSpawnChoose(focus)}>
                <Navigation size={16} aria-hidden="true" />
                {labels.spawnGo}
              </Button>
            </div>
          </div>
        </Surface>
      </div>
      <Text variant="small" className="absolute bottom-[6%] right-16 text-white/50">
        {labels.spawnHint}
      </Text>
    </div>
  );
}
