import { z } from "zod";

import { FIRST_CATCH_GOALS, FIRST_CATCH_INTERESTS } from "./learning-preference-options";

export { FIRST_CATCH_GOALS, FIRST_CATCH_INTERESTS };
export const DailyMinutesSchema = z.union([
  z.literal(5),
  z.literal(10),
  z.literal(15),
  z.literal(30),
  z.literal(60),
]);
export const LearningPreferencesSchema = z.object({
  dailyMinutes: DailyMinutesSchema,
  goals: z.array(z.enum(FIRST_CATCH_GOALS)).max(6).default([]),
  interests: z.array(z.enum(FIRST_CATCH_INTERESTS)).max(9).default([]),
});
export type LearningPreferences = z.infer<typeof LearningPreferencesSchema>;
export function learningPreferencesOf(value: unknown): LearningPreferences | null {
  const result = LearningPreferencesSchema.safeParse(value);
  return result.success ? result.data : null;
}
export function learningPreferencesKey(value: LearningPreferences): string {
  return JSON.stringify({
    goals: [...new Set(value.goals)].sort(),
    interests: [...new Set(value.interests)].sort(),
    dailyMinutes: value.dailyMinutes,
  });
}
/** Preferences are private user-editable content, never authorization claims. */
export function personalizationRule(prefs: LearningPreferences): string {
  const goals: Record<LearningPreferences["goals"][number], string> = {
    conversation: "everyday conversations with friends and neighbors",
    travel: "travel, study abroad, asking directions, ordering and shopping",
    work: "workplace conversations and professional situations",
    exams: "useful language for exam speaking and writing; do not claim official exam provenance",
    culture: "hobbies and cultural experiences",
    other: "natural everyday situations",
  };
  const interests: Record<LearningPreferences["interests"][number], string> = {
    food: "food, drinks and cafes",
    travel: "travel",
    animals: "animals and pets",
    nature: "nature and the outdoors",
    city: "cities and architecture",
    fashion: "clothing and fashion",
    business: "business",
    music: "music and films",
    sports: "sports and exercise",
  };
  return `Learner goals: ${prefs.goals.map((x) => goals[x]).join("; ") || "everyday communication"}.
Interests: ${prefs.interests.map((x) => interests[x]).join("; ") || "everyday life"}.
Daily study preference: ${prefs.dailyMinutes} minutes. Keep explanations approachable and concise.
Choose natural example situations related to these goals and interests when the word actually fits. Explain why and when someone would say it in that situation. Do not force an unrelated interest into a sentence, change the word's true meaning, infer personal facts, or invent extra senses. Multiple choices should influence varied examples, not all be crammed into one sentence.`;
}
