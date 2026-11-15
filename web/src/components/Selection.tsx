/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useCallback, useEffect, useState } from "react";
import { Calendar, Clock, HeartPulse, MapPin, Play, Plus, Skull, Trash2 } from "lucide-react";
import { DeleteDialog } from "@/components/DeleteDialog";
import { Button } from "@/components/ui/Button";
import { Surface } from "@/components/ui/Surface";
import { Text } from "@/components/ui/Text";
import { cn } from "@/lib/cn";
import { fill, formatBirthDate, formatPlayed, initials } from "@/lib/format";
import { sendHover, sendSelect } from "@/lib/nui";
import { BRAND_BAR, BRAND_FILL, TONES, toneAt, type ToneClasses } from "@/lib/tones";
import { useSceneStore } from "@/store/sceneStore";
import { DeathState, Detail as DetailKind, Place, Side, type SlotView } from "@/types/protocol";

function Detail({ icon: Icon, label, value, tone }: { icon: typeof Clock; label: string; value: string; tone: ToneClasses }) {
  return (
    <div className="flex items-center gap-3">
      <span className={cn("flex h-8 w-8 shrink-0 items-center justify-center rounded-lg", tone.chip)}>
        <Icon size={16} aria-hidden="true" />
      </span>
      <div className="min-w-0">
        <Text variant="small" className="text-muted-foreground">
          {label}
        </Text>
        <Text variant="body" className="truncate text-foreground">
          {value}
        </Text>
      </div>
    </div>
  );
}

/** The focused slot, large: who they are and the main action. */
function Panel({ slot, count, onDelete }: { slot: SlotView; count: number; onDelete: () => void }) {
  const { labels, locale, details } = useSceneStore((state) => state.config);
  const allowDelete = useSceneStore((state) => state.form.allowDelete);
  const character = slot.character;

  return (
    <Surface
      key={slot.index}
      variant="glass"
      padding="none"
      className="pointer-events-auto w-96 overflow-hidden animate-ug-slide-up"
    >
      <div className={BRAND_BAR} />
      <div className="flex flex-col gap-5 p-6">
        <Text variant="small" className={cn("uppercase tracking-[0.25em]", toneAt(slot.index).text)}>
          {fill(labels.slot ?? "", { index: slot.index, count })}
        </Text>

        {character ? (
          <>
            <div className="flex flex-col gap-2">
              <h2 className="text-4xl font-semibold leading-tight text-foreground">{character.name}</h2>
              {character.deathState !== DeathState.Alive && (
                <span className="inline-flex w-fit items-center gap-1.5 rounded-md bg-destructive px-2 py-1 text-xs font-medium text-destructive-foreground">
                  {character.deathState === DeathState.Dead ? <Skull size={14} aria-hidden="true" /> : <HeartPulse size={14} aria-hidden="true" />}
                  {character.deathState === DeathState.Dead ? labels.dead : labels.downed}
                </span>
              )}
            </div>
            {details.length > 0 && (
              <div data-details className="flex flex-col gap-3">
                {details.map((kind) => {
                  switch (kind) {
                    case DetailKind.Born:
                      return (
                        character.birthDate && (
                          <Detail key={kind} icon={Calendar} tone={TONES.amber} label={labels.born ?? ""} value={formatBirthDate(character.birthDate, locale)} />
                        )
                      );
                    case DetailKind.LastPlayed:
                      return (
                        <Detail
                          key={kind}
                          icon={Clock}
                          tone={TONES.sky}
                          label={labels.lastPlayed ?? ""}
                          value={character.lastPlayed !== undefined ? formatPlayed(character.lastPlayed, locale) : (labels.never ?? "")}
                        />
                      );
                    case DetailKind.Location:
                      return character.street && <Detail key={kind} icon={MapPin} tone={TONES.emerald} label={labels.location ?? ""} value={character.street} />;
                    default:
                      return null;
                  }
                })}
              </div>
            )}
            <div className="flex gap-2">
              <Button className={cn("h-11 flex-1 text-base", BRAND_FILL)} onClick={() => void sendSelect(slot.index)}>
                <Play size={16} aria-hidden="true" />
                {labels.play}
              </Button>
              {allowDelete && (
                <Button variant="outline" className="h-11 w-11 px-0 hover:border-destructive hover:text-destructive" aria-label={labels.delete} onClick={onDelete}>
                  <Trash2 size={16} aria-hidden="true" />
                </Button>
              )}
            </div>
          </>
        ) : (
          <>
            <h2 className="text-3xl font-semibold text-foreground/80">{labels.empty}</h2>
            <Button className={cn("h-11 text-base", BRAND_FILL)} onClick={() => void sendSelect(slot.index)}>
              <Plus size={16} aria-hidden="true" />
              {labels.create}
            </Button>
          </>
        )}
      </div>
    </Surface>
  );
}

/** One card per slot along the bottom. */
function SlotBar({ slots, focus }: { slots: SlotView[]; focus: number }) {
  const labels = useSceneStore((state) => state.config.labels);
  const initialsOn = useSceneStore((state) => state.config.layout.initials);

  return (
    <div role="listbox" aria-label={labels.slot} className="pointer-events-auto flex gap-3">
      {slots.map((slot) => {
        const active = slot.index === focus;
        const tone = toneAt(slot.index);

        return (
          <button
            key={slot.index}
            type="button"
            role="option"
            aria-selected={active}
            aria-label={slot.character?.name ?? labels.empty}
            onMouseEnter={() => {
              if (!active) {
                useSceneStore.getState().setFocus(slot.index);
                void sendHover(slot.index);
              }
            }}
            onClick={() => void sendSelect(slot.index)}
            className={cn(
              "flex h-16 w-44 items-center gap-3 rounded-lg border px-3 text-left transition-all duration-300",
              active ? cn("-translate-y-1 bg-card/95 shadow-ug-lg", tone.border) : "border-white/10 bg-card/70 hover:bg-card/85",
            )}
          >
            <span
              className={cn(
                "flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-sm font-semibold",
                slot.character ? cn(tone.fill, "text-white", !active && "opacity-70") : "border border-dashed border-muted-foreground/50 text-muted-foreground",
              )}
              aria-hidden="true"
            >
              {slot.character ? (initialsOn ? initials(slot.character.name) : null) : <Plus size={16} />}
            </span>
            <span className={cn("truncate text-sm", slot.character ? "text-foreground" : "text-muted-foreground")}>
              {slot.character?.name ?? labels.empty}
            </span>
          </button>
        );
      })}
    </div>
  );
}

/** The selection screen: the focused slot on the left, every slot along the bottom. Arrows and Enter work too. */
export function Selection() {
  const slots = useSceneStore((state) => state.slots);
  const focus = useSceneStore((state) => state.focus);
  const hint = useSceneStore((state) => state.config.labels.hint);
  const layout = useSceneStore((state) => state.config.layout);
  const current = slots.find((slot) => slot.index === focus) ?? slots[0];
  const [deleting, setDeleting] = useState<SlotView | null>(null);
  const closeDialog = useCallback(() => setDeleting(null), []);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const { slots: all, focus: index, setFocus, dialogOpen, config } = useSceneStore.getState();

      if (all.length === 0 || dialogOpen || !config.layout.keyboard) {
        return;
      }

      if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
        const next = event.key === "ArrowLeft" ? ((index - 2 + all.length) % all.length) + 1 : (index % all.length) + 1;

        setFocus(next);
        void sendHover(next);
      } else if (event.key === "Enter") {
        void sendSelect(index);
      }
    };

    window.addEventListener("keydown", onKey);

    return () => window.removeEventListener("keydown", onKey);
  }, []);

  if (!current) {
    return null;
  }

  return (
    <div className="pointer-events-none fixed inset-0">
      <div data-panel={layout.side} className={cn("absolute top-1/2 -translate-y-1/2", layout.side === Side.Right ? "right-16" : "left-16")}>
        <Panel slot={current} count={slots.length} onDelete={() => setDeleting(current)} />
      </div>
      <div data-slots={layout.slots} className={cn("absolute inset-x-0 flex justify-center", layout.slots === Place.Top ? "top-[8%]" : "bottom-[11%]")}>
        <SlotBar slots={slots} focus={focus} />
      </div>
      {layout.hint && (
        <Text data-hint variant="small" className={cn("absolute bottom-[6%] text-white/50", layout.side === Side.Right ? "left-16" : "right-16")}>
          {hint}
        </Text>
      )}
      {deleting?.character && <DeleteDialog index={deleting.index} name={deleting.character.name} onClose={closeDialog} />}
    </div>
  );
}
