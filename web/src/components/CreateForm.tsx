/*

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

import { useEffect, useMemo, useState, type FormEvent } from "react";
import { ArrowLeft, UserPlus } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { Surface } from "@/components/ui/Surface";
import { Text } from "@/components/ui/Text";
import { cn } from "@/lib/cn";
import { BRAND_BAR, BRAND_FILL } from "@/lib/tones";
import { fill, resultLabel } from "@/lib/format";
import { sendCancel, sendModel, sendSubmit } from "@/lib/nui";
import { checkField, type FieldError } from "@/lib/validation";
import { useSceneStore } from "@/store/sceneStore";
import { FieldType, type FormField } from "@/types/protocol";

const ERROR_LABELS: Record<FieldError, string> = {
  required: "errorRequired",
  length: "errorLength",
  symbols: "errorSymbols",
  spaces: "errorSpaces",
  date: "errorDate",
  age: "errorAge",
  option: "errorOption",
};

/** Labels for the freemode models. Other models show their name. */
const MODEL_LABELS: Record<string, string> = {
  mp_m_freemode_01: "modelMale",
  mp_f_freemode_01: "modelFemale",
};

const inputClass =
  "h-10 w-full rounded-md border bg-background/60 px-3 text-sm text-foreground placeholder:text-muted-foreground transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring";

function Choice({ options, value, onChange, label }: { options: { value: string; label: string }[]; value: string; onChange: (value: string) => void; label: string }) {
  return (
    <div role="radiogroup" aria-label={label} className="flex flex-wrap gap-1 rounded-md bg-muted p-1">
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          role="radio"
          aria-checked={option.value === value}
          onClick={() => onChange(option.value)}
          className={cn(
            "flex-1 rounded px-3 py-1.5 text-sm font-medium transition-colors",
            option.value === value ? "bg-primary text-primary-foreground shadow-ug-sm" : "text-muted-foreground hover:text-foreground",
          )}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

/** The creation screen: the owner's fields and a body, next to the new character in the scene. */
export function CreateForm() {
  const { fields, ageRange, models } = useSceneStore((state) => state.form);
  const labels = useSceneStore((state) => state.config.labels);
  const result = useSceneStore((state) => state.result);
  const [values, setValues] = useState<Record<string, string>>(() => Object.fromEntries(fields.map((field) => [field.name, ""])));
  const [model, setModel] = useState(models[0] ?? "");
  const [submitted, setSubmitted] = useState(false);
  const [pending, setPending] = useState(false);

  const errors = useMemo(() => {
    const found: Record<string, FieldError> = {};

    for (const field of fields) {
      const error = checkField(field, values[field.name] ?? "", ageRange);

      if (error) {
        found[field.name] = error;
      }
    }

    return found;
  }, [fields, values, ageRange]);

  // A refused create lets the player try again.
  useEffect(() => {
    if (result) {
      setPending(false);
    }
  }, [result]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        void sendCancel();
      }
    };

    window.addEventListener("keydown", onKey);

    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const errorText = (field: FormField): string | undefined => {
    const error = errors[field.name];

    if (!error || (!submitted && (values[field.name] ?? "") === "")) {
      return undefined;
    }

    const template = labels[ERROR_LABELS[error]] ?? error;

    return error === "age" ? fill(template, ageRange) : fill(template, { min: field.min ?? 1, max: field.max ?? 64 });
  };

  const submit = (event: FormEvent) => {
    event.preventDefault();
    setSubmitted(true);

    if (Object.keys(errors).length === 0 && model && !pending) {
      setPending(true);
      void sendSubmit(values, model);
    }
  };

  const chooseModel = (value: string) => {
    setModel(value);
    void sendModel(value);
  };

  return (
    <div className="pointer-events-none fixed inset-0">
      <form onSubmit={submit} className="absolute left-16 top-1/2 -translate-y-1/2" noValidate>
        <Surface variant="glass" padding="none" className="pointer-events-auto w-[26rem] overflow-hidden animate-ug-slide-up">
          <div className={BRAND_BAR} />
          <div className="flex flex-col gap-5 p-6">
            <h2 className="text-3xl font-semibold text-foreground">{labels.createTitle}</h2>

            {fields.map((field) => {
              const error = errorText(field);
              const id = `field-${field.name}`;

              return (
                <div key={field.name} className="flex flex-col gap-1.5">
                  <label htmlFor={id} className="text-sm font-medium text-foreground">
                    {field.label}
                  </label>
                  {field.type === FieldType.Select ? (
                    <Choice
                      label={field.label}
                      options={field.options ?? []}
                      value={values[field.name] ?? ""}
                      onChange={(value) => setValues((previous) => ({ ...previous, [field.name]: value }))}
                    />
                  ) : (
                    <input
                      id={id}
                      type={field.type === FieldType.Date ? "date" : "text"}
                      autoComplete="off"
                      maxLength={field.type === FieldType.Text ? (field.max ?? 64) : 10}
                      value={values[field.name] ?? ""}
                      aria-invalid={error ? true : undefined}
                      onChange={(event) => setValues((previous) => ({ ...previous, [field.name]: event.target.value }))}
                      className={cn(inputClass, error ? "border-destructive" : "border-input")}
                    />
                  )}
                  {error && (
                    <Text variant="small" className="text-destructive" role="alert">
                      {error}
                    </Text>
                  )}
                </div>
              );
            })}

            {models.length > 1 && (
              <div className="flex flex-col gap-1.5">
                <span className="text-sm font-medium text-foreground">{labels.model}</span>
                <Choice
                  label={labels.model ?? ""}
                  value={model}
                  onChange={chooseModel}
                  options={models.map((value) => ({ value, label: labels[MODEL_LABELS[value] ?? ""] ?? value }))}
                />
              </div>
            )}

            {/* Without an error the step was cancelled, such as the appearance editor: the form only unlocks. */}
            {result && !result.ok && result.error && (
              <Text variant="small" className="rounded-md bg-destructive px-3 py-2 text-destructive-foreground" role="alert">
                {labels[resultLabel(result.error)]}
              </Text>
            )}

            <div className="flex gap-2">
              <Button type="button" variant="outline" className="h-11" onClick={() => void sendCancel()}>
                <ArrowLeft size={16} aria-hidden="true" />
                {labels.back}
              </Button>
              <Button type="submit" className={cn("h-11 flex-1 text-base", BRAND_FILL)} disabled={pending}>
                <UserPlus size={16} aria-hidden="true" />
                {labels.submit}
              </Button>
            </div>
          </div>
        </Surface>
      </form>
    </div>
  );
}
