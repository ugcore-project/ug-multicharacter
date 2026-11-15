/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useEffect, useState, type FormEvent } from "react";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { Surface } from "@/components/ui/Surface";
import { Text } from "@/components/ui/Text";
import { fill, resultLabel } from "@/lib/format";
import { sendDelete } from "@/lib/nui";
import { useSceneStore } from "@/store/sceneStore";
import { ResultKind } from "@/types/protocol";

/** Deleting asks for the character's name, typed exactly. The server enforces its own cooldown. */
export function DeleteDialog({ index, name, onClose }: { index: number; name: string; onClose: () => void }) {
  const labels = useSceneStore((state) => state.config.labels);
  const result = useSceneStore((state) => state.result);
  const [typed, setTyped] = useState("");
  const [pending, setPending] = useState(false);

  useEffect(() => {
    useSceneStore.setState({ dialogOpen: true, result: null });

    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        onClose();
      }
    };

    window.addEventListener("keydown", onKey);

    return () => {
      window.removeEventListener("keydown", onKey);
      useSceneStore.setState({ dialogOpen: false });
    };
  }, [onClose]);

  useEffect(() => {
    if (result?.kind === ResultKind.Delete) {
      setPending(false);

      if (result.ok) {
        onClose();
      }
    }
  }, [result, onClose]);

  const confirm = (event: FormEvent) => {
    event.preventDefault();

    if (typed === name && !pending) {
      setPending(true);
      void sendDelete(index);
    }
  };

  return (
    <div className="pointer-events-auto fixed inset-0 flex items-center justify-center bg-background/60 animate-ug-fade-in">
      <form onSubmit={confirm} role="dialog" aria-label={fill(labels.deleteTitle ?? "", { name })}>
        <Surface variant="solid" padding="none" className="w-[26rem] overflow-hidden animate-ug-scale-in">
          <div className="h-0.5 bg-destructive" />
          <div className="flex flex-col gap-4 p-6">
            <h2 className="text-xl font-semibold text-foreground">{fill(labels.deleteTitle ?? "", { name })}</h2>
            <Text variant="small" className="text-muted-foreground">
              {fill(labels.deleteHint ?? "", { name })}
            </Text>
            <input
              autoFocus
              autoComplete="off"
              aria-label={fill(labels.deleteHint ?? "", { name })}
              value={typed}
              maxLength={64}
              onChange={(event) => setTyped(event.target.value)}
              className="h-10 w-full rounded-md border border-input bg-background/60 px-3 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-destructive"
            />
            {result?.kind === ResultKind.Delete && !result.ok && (
              <Text variant="small" className="rounded-md bg-destructive px-3 py-2 text-destructive-foreground" role="alert">
                {labels[resultLabel(result.error)]}
              </Text>
            )}
            <div className="flex justify-end gap-2">
              <Button type="button" variant="outline" onClick={onClose}>
                {labels.cancel}
              </Button>
              <Button type="submit" variant="destructive" disabled={typed !== name || pending}>
                <Trash2 size={16} aria-hidden="true" />
                {labels.delete}
              </Button>
            </div>
          </div>
        </Surface>
      </form>
    </div>
  );
}
