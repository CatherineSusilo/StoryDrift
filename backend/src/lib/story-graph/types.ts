export type StoryMode = 'bedtime' | 'educational';
export type ArcPosition = 'opening' | 'rising' | 'climax' | 'winding_down' | 'resolved';
export type DriftTrajectory = 'rising' | 'flat' | 'falling';

export interface ChildProfile {
  childId: string;
  name: string;
  age: number;
  favoriteAnimal?: string;
  favoritePlace?: string;
  favoriteCharacter?: string;
  preferredWorld?: 'forest' | 'ocean' | 'space' | 'village';
  tonightsMood?: 'wound_up' | 'normal' | 'almost_there';
}

export interface CharacterState {
  name: string;
  description: string;
  lastAction: string;
  location: string;
}

export interface LessonPlan {
  concept_sequence: string[];
  character_challenge: string;
  reinforcement_moments: string[];
  success_condition: string;
}

export interface StorySegment {
  text: string;
  imageUrl?: string;     // permanent local URL served by Express (e.g. /images/abc.webp)
  falImageUrl?: string;  // temporary Fal.ai CDN URL — used as reference for next image-to-image call
  audioUrl?: string;
  timestamp: number;
  score: number;
  strategy: string;
}

// Raw biometric data from iOS camera (SmartSpectra + MediaPipe)
export interface BiometricInput {
  pulse_rate?: number;          // BPM (e.g. 60-120)
  breathing_rate?: number;      // breaths per minute (e.g. 12-20)
  movement_level?: number;      // 0-1 (0 = still, 1 = very active)
  expression_tone?: number;     // 0-1 (0 = distressed/bored, 1 = calm/curious)
  eye_focus?: number;           // 0-1 (0 = wandering, 1 = on screen) – educational only
  signal_quality?: number;      // 0-1 confidence in readings
}

// Normalized biometric signals after reading
export interface NormalizedBiometrics {
  calm_indicator: number;       // 0-1 (from pulse)
  settling_indicator: number;   // 0-1 (from breathing)
  restlessness_indicator: number; // 0-1 inverted (0=still, 1=restless)
  emotional_state: number;      // 0-1 calm
  focus_indicator: number;      // 0-1 (eye focus, educational)
  signal_quality: number;       // 0-1
}

// Bedtime narrative strategies
export type BedtimeStrategy = 'engagement' | 'settling' | 'winding_down' | 'resolution';

export interface NarrativeStrategy {
  strategy: BedtimeStrategy;
  prompt_directive: string;
}

// Educational strategies
export type EducationalStrategy = 're_engagement' | 'concept_introduction' | 'optimal_learning' | 'consolidation';

export interface EducationalStrategyResult {
  strategy: EducationalStrategy;
  prompt_directive: string;
  next_concept?: string;
  hold_concept: boolean;
}

// ── Bedtime State ──────────────────────────────────────────────────────────────

export interface BedtimeState {
  mode: 'bedtime';
  sessionId: string;
  childId: string;
  childProfile: ChildProfile;

  drift_score: number;
  drift_trajectory: DriftTrajectory;
  drift_score_history: number[];

  story_context: string;
  characters: Record<string, CharacterState>;
  arc_position: ArcPosition;
  session_minutes: number;
  guard_failures: number;

  current_segment?: string;
  current_image_url?: string;
  current_audio_url?: string;
  current_strategy?: BedtimeStrategy;

  segments: StorySegment[];
  sleep_onset_time?: string;
  session_complete: boolean;
}

// ── Educational State ──────────────────────────────────────────────────────────

export interface EducationalState {
  mode: 'educational';
  sessionId: string;
  childId: string;
  childProfile: ChildProfile;

  engagement_score: number;
  engagement_trajectory: DriftTrajectory;
  engagement_score_history: number[];

  lesson_name: string;
  lesson_description: string;
  lesson_plan?: LessonPlan;
  lesson_progress: number;      // 0-100
  concepts_introduced: string[];
  concepts_reinforced: string[];

  story_context: string;
  characters: Record<string, CharacterState>;
  session_minutes: number;
  guard_failures: number;

  current_segment?: string;
  current_image_url?: string;
  current_audio_url?: string;
  current_strategy?: EducationalStrategy;

  segments: StorySegment[];
  minigame_events: MinigameEvent[];
  segments_since_last_minigame: number;
  minigame_frequency: 'none' | 'every_5th' | 'every_3rd' | 'every_paragraph';
  session_complete: boolean;
}

export type GraphState = BedtimeState | EducationalState;

// ── Minigame system ────────────────────────────────────────────────────────────

export type MinigameType = 'drawing' | 'voice' | 'shape_sorting' | 'multiple_choice';

export interface MinigameChoice {
  id: string;
  label: string;
  emoji?: string;
  isCorrect: boolean;
}

export interface ShapeSlot {
  id: string;
  shape: 'circle' | 'square' | 'triangle' | 'star' | 'heart';
  color: string;
  targetSlotId: string;
}

export interface MinigameTrigger {
  type: MinigameType;
  narratorPrompt: string;       // What ElevenLabs says to introduce the minigame
  drawingTheme?: string;        // e.g. "a sword for the night"
  drawingDarkBackground?: boolean;
  voiceTarget?: string;         // e.g. "moo" — what the child should say
  voiceHint?: string;           // e.g. "What sound does a cow make?"
  choices?: MinigameChoice[];   // multiple_choice options
  shapes?: ShapeSlot[];         // shape_sorting pieces
  timeoutSeconds?: number;      // how long before auto-skip (default 30)
}

export interface MinigameResult {
  type: MinigameType;
  completed: boolean;
  correct?: boolean;
  skipped: boolean;
  responseData?: string;        // base64 drawing / transcribed word / chosen id
}

// ── Session tick response ──────────────────────────────────────────────────────

export interface TickResult {
  segment: string;
  imageUrl?: string;
  audioUrl?: string;
  strategy: string;
  score: number;
  trajectory: DriftTrajectory;
  arcPosition?: ArcPosition;
  lessonProgress?: number;
  minigame?: MinigameTrigger;   // present when a minigame should fire after this segment
  sessionComplete: boolean;
  state: GraphState;
}

// Add minigame tracking to educational state
export interface MinigameEvent {
  type: MinigameType;
  segmentIndex: number;
  result?: MinigameResult;
  triggeredAt: number;
}
