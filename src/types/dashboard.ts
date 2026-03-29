// Types that match EXACTLY what spark-sync-state.yml produces in state.json v3

export interface DashboardState {
  lastSync: string
  syncSource: string
  controller: ComponentState
  agent: ComponentState
  pipeline: PipelineState
  agents: AgentsState
  sessionLock: SessionLock
  health: Record<string, any>
  ciMonitor: CIMonitor
  workspaces: Workspace[]
  recentWorkflows: WorkflowRun[]
  openPRs: PullRequest[]
  deployHistory: string[]
  lessonsLearned: LessonsLearned
  versionRules: VersionRules
  executionHistory: ExecutionEntry[]
  knownErrors: KnownError[]
  pipelineStages: PipelineStage[]
  corporateReal: CorporateReal
  metadata: Metadata
  // Computed locally
  lastUpdated: string
}

export interface ComponentState {
  version: string
  status: string
  ciResult: string
  promoted: boolean
  lastSha: string
  updatedAt: string | null
  repo?: string
  capRepo?: string
  stack?: string
}

export interface PipelineState {
  status: string
  lastRun: number
  component: string
  version: string
  promote: boolean
  workspace: string
  changeType?: string
  commitMessage?: string
  changesCount?: number
}

export interface AgentsState {
  claude: ClaudeAgent
  copilot: BotAgent
  codex: BotAgent
}

export interface ClaudeAgent {
  status: string
  task: string | null
  phase: string | null
  lastUpdated: string | null
  lastAction: string | null
}

export interface BotAgent {
  sessionCount: number
  lastSession: string
  lessonsCount: number
  lastUpdated: string | null
  sessions?: AgentSession[]
}

export interface AgentSession {
  date: string
  summary: string
  actions: number
}

export interface SessionLock {
  agentId: string
  expiresAt: string | null
  acquiredAt: string | null
  operation: string | null
}

export interface CIMonitor {
  ciOutcome?: string
  component?: string
  commitSha?: string
}

export interface Workspace {
  id: string
  company: string
  status: string
  stack: string | null
  token: string | null
  controllerVersion: string | null
  agentVersion: string | null
  pipelineStatus: string
  repos: string[]
}

export interface WorkflowRun {
  name: string
  status: string
  conclusion: string | null
  created: string
  url: string
  run_number?: number
  head_branch?: string
  event?: string
}

export interface PullRequest {
  number: number
  title: string
  author: string
  branch: string
  draft: boolean
  created: string
  labels?: string[]
}

export interface LessonsLearned {
  total: number
  copilot: number
  codex: number
  copilotLessons?: LessonEntry[]
  codexLessons?: LessonEntry[]
}

export interface LessonEntry {
  lesson: string
  fix?: string
  source?: string
}

export interface VersionRules {
  currentController: string
  currentAgent: string
  pattern: string
  lastTriggerRun: number
  lastSuccessfulRun: number
}

export interface ExecutionEntry {
  id: string
  date: string
  summary: string
}

export interface KnownError {
  code: string
  desc: string
  fix: string
}

export interface PipelineStage {
  name: string
  desc: string
}

export interface CorporateReal {
  description?: string
  controller: CorporateComponent
  agent: CorporateComponent
  lastChecked: string
}

export interface CorporateComponent {
  sourceVersion: string
  capTag: string
  recentCommits?: CorporateCommit[]
  drift: boolean
  driftDetail: string | null
}

export interface CorporateCommit {
  sha: string
  message: string
  author: string
  date: string
}

export interface Metadata {
  autopilotRepo: string
  sparkRepo: string
  totalAgents: number
  totalWorkspaces: number
  syncInterval: string
  stateVersion: number
}
