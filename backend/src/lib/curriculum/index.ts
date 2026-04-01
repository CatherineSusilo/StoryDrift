/**
 * Hardcoded Duolingo-style curriculum for ages 2-3.
 *
 * Structure:
 *   AgeGroup → Section[] → Lesson[]
 *
 * Each lesson has:
 *   - concepts to teach
 *   - story themes / setting hints for the AI story generator
 *   - minigame schedule: which segment indices should fire a minigame, and what type
 *   - expected number of story segments (ticks)
 *
 * Minigame placement is LESSON-LEVEL, not per-frame frequency.
 * The graph tick checks `lesson.minigameSlots` to decide whether to fire.
 */

// ── Types ────────────────────────────────────────────────────────────────────

export type MinigameSlotType = 'drawing' | 'voice' | 'shape_sorting' | 'multiple_choice';

export interface MinigameSlot {
  afterSegment: number;           // fire after this segment index (0-based)
  preferredType: MinigameSlotType;
  hint?: string;                  // optional context hint for the AI minigame generator
}

export interface CurriculumLesson {
  id: string;                     // e.g. "abc_01"
  order: number;                  // position in section roadmap (1-based)
  name: string;
  description: string;
  concepts: string[];             // concepts to teach
  storyTheme: string;             // theme hint for story generator
  expectedSegments: number;       // expected total ticks
  minigameSlots: MinigameSlot[];  // exact minigame placements
  unlockAfter?: string;           // lesson id that must be completed first (null = first lesson)
}

export interface CurriculumSection {
  id: string;                     // e.g. "abc"
  name: string;
  description: string;
  emoji: string;
  color: string;                  // hex color for UI
  lessons: CurriculumLesson[];
}

export interface AgeGroup {
  ageRange: string;               // e.g. "2-3"
  minAge: number;
  maxAge: number;
  sections: CurriculumSection[];
}

// ── Curriculum Data: Ages 2-3 ────────────────────────────────────────────────

const ABC_SECTION: CurriculumSection = {
  id: 'abc',
  name: 'ABC — Letters & Sounds',
  description: 'Learn to recognise letters and the sounds they make',
  emoji: '🔤',
  color: '#FF6B6B',
  lessons: [
    {
      id: 'abc_01', order: 1,
      name: 'Meet Letter A',
      description: 'Introduction to the letter A and its sound',
      concepts: ['letter A', 'A sound /æ/', 'apple starts with A'],
      storyTheme: 'A magical apple tree in a friendly forest',
      expectedSegments: 5,
      minigameSlots: [],  // first lesson: no minigames, pure story
    },
    {
      id: 'abc_02', order: 2,
      name: 'Letter A Adventures',
      description: 'Practise recognising A in words and sounds',
      concepts: ['A sound /æ/', 'ant', 'airplane', 'alligator'],
      storyTheme: 'An ant and an alligator go on an airplane adventure',
      expectedSegments: 6,
      minigameSlots: [
        { afterSegment: 5, preferredType: 'voice', hint: 'Say the /æ/ sound like an ant!' },
      ],
      unlockAfter: 'abc_01',
    },
    {
      id: 'abc_03', order: 3,
      name: 'Meet Letter B',
      description: 'Introduction to the letter B and its sound',
      concepts: ['letter B', 'B sound /b/', 'bear', 'ball', 'butterfly'],
      storyTheme: 'A bear plays with a big bouncy ball near beautiful butterflies',
      expectedSegments: 6,
      minigameSlots: [
        { afterSegment: 3, preferredType: 'multiple_choice', hint: 'Which animal starts with B?' },
        { afterSegment: 5, preferredType: 'voice', hint: 'Say Buh-Buh-Bear!' },
      ],
      unlockAfter: 'abc_02',
    },
    {
      id: 'abc_04', order: 4,
      name: 'A & B Together',
      description: 'Review letters A and B — compare their sounds',
      concepts: ['letter A review', 'letter B review', 'A vs B sounds'],
      storyTheme: 'An ant and a bear become friends and go on a trip',
      expectedSegments: 7,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'multiple_choice', hint: 'Does this word start with A or B?' },
        { afterSegment: 5, preferredType: 'drawing', hint: 'Draw something that starts with B' },
        { afterSegment: 6, preferredType: 'voice', hint: 'Say A then B!' },
      ],
      unlockAfter: 'abc_03',
    },
    {
      id: 'abc_05', order: 5,
      name: 'Meet Letter C',
      description: 'Introduction to the letter C and its sound',
      concepts: ['letter C', 'C sound /k/', 'cat', 'cow', 'cake'],
      storyTheme: 'A curious cat finds a colorful cake in a cozy cottage',
      expectedSegments: 6,
      minigameSlots: [
        { afterSegment: 3, preferredType: 'voice', hint: 'What sound does a cow make? Moo!' },
        { afterSegment: 5, preferredType: 'multiple_choice', hint: 'Which starts with C?' },
      ],
      unlockAfter: 'abc_04',
    },
    {
      id: 'abc_06', order: 6,
      name: 'A, B, C Song',
      description: 'Review all three letters — sing and play',
      concepts: ['A B C sequence', 'letter recognition', 'phonics review'],
      storyTheme: 'Three friends — Ant, Bear, Cat — put on a show and sing the ABC song',
      expectedSegments: 7,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'voice', hint: 'Sing A-B-C!' },
        { afterSegment: 4, preferredType: 'shape_sorting', hint: 'Match the letter to its picture' },
        { afterSegment: 6, preferredType: 'drawing', hint: 'Draw your favourite letter' },
      ],
      unlockAfter: 'abc_05',
    },
  ],
};

const COUNTING_SECTION: CurriculumSection = {
  id: 'counting',
  name: 'Counting — Numbers 1-10',
  description: 'Learn to count objects and recognise numbers',
  emoji: '🔢',
  color: '#4ECDC4',
  lessons: [
    {
      id: 'count_01', order: 1,
      name: 'One is Fun',
      description: 'The concept of "one" — one ball, one sun, one me',
      concepts: ['number 1', 'one object', 'counting one thing'],
      storyTheme: 'A child finds one special star in the night sky',
      expectedSegments: 5,
      minigameSlots: [],
    },
    {
      id: 'count_02', order: 2,
      name: 'Two Together',
      description: 'Pairs and the number two',
      concepts: ['number 2', 'pairs', 'two eyes, two hands'],
      storyTheme: 'Two bunny friends go on an adventure to find matching socks',
      expectedSegments: 6,
      minigameSlots: [
        { afterSegment: 5, preferredType: 'multiple_choice', hint: 'How many bunnies are there?' },
      ],
      unlockAfter: 'count_01',
    },
    {
      id: 'count_03', order: 3,
      name: 'Three Little Things',
      description: 'Counting to three and recognising groups of three',
      concepts: ['number 3', 'counting to 3', 'triangle has 3 sides'],
      storyTheme: 'Three little birds build nests in a big tree',
      expectedSegments: 6,
      minigameSlots: [
        { afterSegment: 3, preferredType: 'shape_sorting', hint: 'Sort 3 shapes into 3 nests' },
        { afterSegment: 5, preferredType: 'voice', hint: 'Count: one, two, three!' },
      ],
      unlockAfter: 'count_02',
    },
    {
      id: 'count_04', order: 4,
      name: 'Four and Five',
      description: 'Counting four and five objects',
      concepts: ['number 4', 'number 5', 'five fingers', 'counting objects'],
      storyTheme: 'Four fish and a friendly octopus count the five fingers on a starfish',
      expectedSegments: 7,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'multiple_choice', hint: 'How many fish are swimming?' },
        { afterSegment: 4, preferredType: 'drawing', hint: 'Draw 5 dots like a starfish' },
        { afterSegment: 6, preferredType: 'voice', hint: 'Count from 1 to 5!' },
      ],
      unlockAfter: 'count_03',
    },
    {
      id: 'count_05', order: 5,
      name: 'Counting to Ten',
      description: 'Count all the way from 1 to 10!',
      concepts: ['numbers 6-10', 'counting sequence', '10 fingers'],
      storyTheme: 'Ten friendly animals line up for a parade through the village',
      expectedSegments: 8,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'voice', hint: 'Count the animals: 1, 2, 3...' },
        { afterSegment: 4, preferredType: 'shape_sorting', hint: 'Put numbers in order' },
        { afterSegment: 7, preferredType: 'multiple_choice', hint: 'What comes after 7?' },
      ],
      unlockAfter: 'count_04',
    },
    {
      id: 'count_06', order: 6,
      name: 'Counting Review Party',
      description: 'Review counting 1-10 with games and celebration',
      concepts: ['1-10 review', 'counting objects', 'number recognition'],
      storyTheme: 'A birthday party with 10 candles on a cake — count them all!',
      expectedSegments: 7,
      minigameSlots: [
        { afterSegment: 1, preferredType: 'voice', hint: 'Count the candles!' },
        { afterSegment: 3, preferredType: 'multiple_choice', hint: 'How many presents?' },
        { afterSegment: 5, preferredType: 'drawing', hint: 'Draw candles on the cake' },
        { afterSegment: 6, preferredType: 'shape_sorting', hint: 'Match numbers to groups' },
      ],
      unlockAfter: 'count_05',
    },
  ],
};

const COLORS_SHAPES_SECTION: CurriculumSection = {
  id: 'colors_shapes',
  name: 'Colors & Shapes',
  description: 'Explore the rainbow and learn basic shapes',
  emoji: '🎨',
  color: '#FF9F43',
  lessons: [
    {
      id: 'cs_01', order: 1,
      name: 'Red and Blue',
      description: 'Meet the colours red and blue',
      concepts: ['red', 'blue', 'colour naming'],
      storyTheme: 'A red ladybug and a blue bluebird explore a garden',
      expectedSegments: 5,
      minigameSlots: [],
    },
    {
      id: 'cs_02', order: 2,
      name: 'Yellow and Green',
      description: 'Meet the colours yellow and green',
      concepts: ['yellow', 'green', 'sun is yellow', 'grass is green'],
      storyTheme: 'A yellow duckling waddles through green grass to find friends',
      expectedSegments: 6,
      minigameSlots: [
        { afterSegment: 5, preferredType: 'multiple_choice', hint: 'What colour is the sun?' },
      ],
      unlockAfter: 'cs_01',
    },
    {
      id: 'cs_03', order: 3,
      name: 'Circles Everywhere',
      description: 'The circle shape — wheels, sun, balls',
      concepts: ['circle', 'round', 'wheel', 'ball'],
      storyTheme: 'A bouncy ball rolls through town finding all the circles',
      expectedSegments: 6,
      minigameSlots: [
        { afterSegment: 3, preferredType: 'drawing', hint: 'Draw a big circle' },
        { afterSegment: 5, preferredType: 'shape_sorting', hint: 'Find all the circles' },
      ],
      unlockAfter: 'cs_02',
    },
    {
      id: 'cs_04', order: 4,
      name: 'Squares and Triangles',
      description: 'Meet squares and triangles — houses, roofs, windows',
      concepts: ['square', 'triangle', '4 sides vs 3 sides', 'house shapes'],
      storyTheme: 'Building a house with squares for walls and a triangle for the roof',
      expectedSegments: 7,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'shape_sorting', hint: 'Match shapes to the house' },
        { afterSegment: 4, preferredType: 'drawing', hint: 'Draw a house with squares and triangles' },
        { afterSegment: 6, preferredType: 'multiple_choice', hint: 'How many sides does a triangle have?' },
      ],
      unlockAfter: 'cs_03',
    },
    {
      id: 'cs_05', order: 5,
      name: 'Rainbow Mix',
      description: 'All colours together — painting a rainbow',
      concepts: ['rainbow', 'colour sequence', 'mixing colours'],
      storyTheme: 'After the rain, friends paint a rainbow across the sky',
      expectedSegments: 7,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'voice', hint: 'Name the colours: red, orange, yellow...' },
        { afterSegment: 4, preferredType: 'drawing', hint: 'Draw a rainbow' },
        { afterSegment: 6, preferredType: 'multiple_choice', hint: 'What colour comes after orange?' },
      ],
      unlockAfter: 'cs_04',
    },
  ],
};

const ANIMALS_SECTION: CurriculumSection = {
  id: 'animals',
  name: 'Animals & Nature',
  description: 'Discover animals, their sounds, and where they live',
  emoji: '🐾',
  color: '#45B7D1',
  lessons: [
    {
      id: 'animals_01', order: 1,
      name: 'Farm Friends',
      description: 'Meet the animals on the farm',
      concepts: ['cow', 'pig', 'chicken', 'farm sounds'],
      storyTheme: 'A day on a friendly farm — meet the cow, pig, and chicken',
      expectedSegments: 5,
      minigameSlots: [],
    },
    {
      id: 'animals_02', order: 2,
      name: 'Animal Sounds',
      description: 'What sound does each animal make?',
      concepts: ['moo', 'oink', 'baa', 'cluck', 'animal matching'],
      storyTheme: 'The farm animals play a guessing game — whose sound is that?',
      expectedSegments: 6,
      minigameSlots: [
        { afterSegment: 3, preferredType: 'voice', hint: 'Moo like a cow!' },
        { afterSegment: 5, preferredType: 'voice', hint: 'Baa like a sheep!' },
      ],
      unlockAfter: 'animals_01',
    },
    {
      id: 'animals_03', order: 3,
      name: 'Forest Animals',
      description: 'Meet deer, owl, rabbit, and fox',
      concepts: ['deer', 'owl', 'rabbit', 'fox', 'forest habitat'],
      storyTheme: 'A nighttime walk through the forest meeting nocturnal animals',
      expectedSegments: 6,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'multiple_choice', hint: 'Which animal says hoo-hoo?' },
        { afterSegment: 5, preferredType: 'drawing', hint: 'Draw a bunny' },
      ],
      unlockAfter: 'animals_02',
    },
    {
      id: 'animals_04', order: 4,
      name: 'Ocean Creatures',
      description: 'Fish, dolphins, turtles, and starfish',
      concepts: ['fish', 'dolphin', 'turtle', 'starfish', 'ocean habitat'],
      storyTheme: 'A submarine adventure to the bottom of the sea',
      expectedSegments: 7,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'voice', hint: 'Splash like a dolphin!' },
        { afterSegment: 4, preferredType: 'multiple_choice', hint: 'How many arms does a starfish have?' },
        { afterSegment: 6, preferredType: 'drawing', hint: 'Draw a fish' },
      ],
      unlockAfter: 'animals_03',
    },
    {
      id: 'animals_05', order: 5,
      name: 'Baby Animals',
      description: 'Match baby animals to their parents',
      concepts: ['kitten/cat', 'puppy/dog', 'calf/cow', 'chick/hen', 'baby names'],
      storyTheme: 'Baby animals got lost! Help them find their mums and dads',
      expectedSegments: 7,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'multiple_choice', hint: 'Whose baby is the kitten?' },
        { afterSegment: 4, preferredType: 'voice', hint: 'Call out: Meow, meow!' },
        { afterSegment: 6, preferredType: 'shape_sorting', hint: 'Match babies to parents' },
      ],
      unlockAfter: 'animals_04',
    },
  ],
};

const BEHAVIORAL_SECTION: CurriculumSection = {
  id: 'behavioral',
  name: 'Feelings & Friendship',
  description: 'Learn about emotions, sharing, kindness, and making friends',
  emoji: '💛',
  color: '#A29BFE',
  lessons: [
    {
      id: 'beh_01', order: 1,
      name: 'Happy and Sad',
      description: 'Recognising happy and sad feelings',
      concepts: ['happy', 'sad', 'feelings', 'facial expressions'],
      storyTheme: 'A teddy bear feels different emotions throughout a rainy day that turns sunny',
      expectedSegments: 5,
      minigameSlots: [],
    },
    {
      id: 'beh_02', order: 2,
      name: 'Sharing is Caring',
      description: 'Why sharing makes everyone happy',
      concepts: ['sharing', 'taking turns', 'generosity', 'fairness'],
      storyTheme: 'Two friends learn to share their toys at the playground',
      expectedSegments: 6,
      minigameSlots: [
        { afterSegment: 5, preferredType: 'multiple_choice', hint: 'What should the bunny do with the extra cookie?' },
      ],
      unlockAfter: 'beh_01',
    },
    {
      id: 'beh_03', order: 3,
      name: 'Making Friends',
      description: 'How to say hi, introduce yourself, and play together',
      concepts: ['greeting', 'introduction', 'playing together', 'friendship'],
      storyTheme: 'A shy kitten goes to a new park and makes a friend',
      expectedSegments: 6,
      minigameSlots: [
        { afterSegment: 3, preferredType: 'voice', hint: 'Say: Hi! My name is...' },
        { afterSegment: 5, preferredType: 'multiple_choice', hint: 'What is a nice way to ask someone to play?' },
      ],
      unlockAfter: 'beh_02',
    },
    {
      id: 'beh_04', order: 4,
      name: 'Please and Thank You',
      description: 'Magic words — being polite and grateful',
      concepts: ['please', 'thank you', 'you\'re welcome', 'politeness', 'manners'],
      storyTheme: 'A little bear discovers that magic words open doors and hearts',
      expectedSegments: 7,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'voice', hint: 'Say: Please!' },
        { afterSegment: 4, preferredType: 'multiple_choice', hint: 'What do you say when someone gives you a gift?' },
        { afterSegment: 6, preferredType: 'voice', hint: 'Say: Thank you!' },
      ],
      unlockAfter: 'beh_03',
    },
    {
      id: 'beh_05', order: 5,
      name: 'Big Feelings',
      description: 'Angry, scared, excited — all feelings are okay',
      concepts: ['angry', 'scared', 'excited', 'calming down', 'deep breaths'],
      storyTheme: 'A little dragon learns to take deep breaths when big feelings come',
      expectedSegments: 7,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'multiple_choice', hint: 'How is the dragon feeling right now?' },
        { afterSegment: 4, preferredType: 'voice', hint: 'Take a deep breath: breathe in... breathe out...' },
        { afterSegment: 6, preferredType: 'drawing', hint: 'Draw a happy face' },
      ],
      unlockAfter: 'beh_04',
    },
    {
      id: 'beh_06', order: 6,
      name: 'Helping Others',
      description: 'Being kind by helping friends and family',
      concepts: ['helping', 'kindness', 'teamwork', 'empathy'],
      storyTheme: 'Forest animals work together to help a bird rebuild its nest after a storm',
      expectedSegments: 7,
      minigameSlots: [
        { afterSegment: 2, preferredType: 'multiple_choice', hint: 'Who needs help?' },
        { afterSegment: 4, preferredType: 'drawing', hint: 'Draw the animals helping together' },
        { afterSegment: 6, preferredType: 'voice', hint: 'Say: Can I help you?' },
      ],
      unlockAfter: 'beh_05',
    },
  ],
};

// ── Age Group Registry ──────────────────────────────────────────────────────

export const CURRICULUM: AgeGroup[] = [
  {
    ageRange: '2-3',
    minAge: 2,
    maxAge: 3,
    sections: [ABC_SECTION, COUNTING_SECTION, COLORS_SHAPES_SECTION, ANIMALS_SECTION, BEHAVIORAL_SECTION],
  },
];

// ── Lookup helpers ──────────────────────────────────────────────────────────

export function getCurriculumForAge(age: number): AgeGroup | undefined {
  return CURRICULUM.find(g => age >= g.minAge && age <= g.maxAge);
}

export function findLesson(lessonId: string): { ageGroup: AgeGroup; section: CurriculumSection; lesson: CurriculumLesson } | undefined {
  for (const ag of CURRICULUM) {
    for (const sec of ag.sections) {
      const lesson = sec.lessons.find(l => l.id === lessonId);
      if (lesson) return { ageGroup: ag, section: sec, lesson };
    }
  }
  return undefined;
}

export function findSection(sectionId: string): { ageGroup: AgeGroup; section: CurriculumSection } | undefined {
  for (const ag of CURRICULUM) {
    const section = ag.sections.find(s => s.id === sectionId);
    if (section) return { ageGroup: ag, section };
  }
  return undefined;
}

/**
 * Given the current segment index (0-based) within a lesson,
 * return the minigame slot if one should fire after this segment, or null.
 */
export function getMinigameSlotForSegment(lessonId: string, segmentIndex: number): MinigameSlot | null {
  const found = findLesson(lessonId);
  if (!found) return null;
  return found.lesson.minigameSlots.find(s => s.afterSegment === segmentIndex) ?? null;
}
