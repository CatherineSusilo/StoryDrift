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
  imageUrl?: string;
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
  session_complete: boolean;
}

export type GraphState = BedtimeState | EducationalState;

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
  sessionComplete: boolean;
  state: GraphState;
}
