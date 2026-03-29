# Planning Guide

A comprehensive CI/CD operations dashboard for monitoring multi-agent deploy systems, providing real-time insights into controller versions, agent activities, pipeline stages, deployment history, analytics, and configurable settings. Enhanced with data visualization, performance metrics, trend analysis, and personalized preferences.

**Experience Qualities**:
1. **Professional** - Clean, information-dense interface that conveys technical authority and operational control
2. **Responsive** - Real-time updates every 30 seconds providing immediate awareness of system state changes
3. **Insightful** - Clear visual hierarchy that surfaces critical information and anomalies at a glance

**Complexity Level**: Complex Application (advanced functionality, likely with multiple views)
This is a multi-view monitoring dashboard with real-time data updates, multiple data visualizations, filtering capabilities, and state management across different operational views.

## Essential Features

### Dashboard Overview
- **Functionality**: Display key system metrics in card format with charts, trends, and quick stats. Shows Controller version, Agent version, last deploy info, pipeline status, trigger run count, active agent, success rate, and deployment trends over time
- **Purpose**: Provide at-a-glance operational awareness of system health, performance trends, and current state
- **Trigger**: Default landing page, accessible from sidebar navigation
- **Progression**: User lands on dashboard → Scans status cards with trends → Reviews charts and success rates → Identifies any issues by color coding → Clicks through to detailed views as needed
- **Success criteria**: All metrics visible without scrolling, color-coded status immediately understood, real-time updates reflect actual system state, charts display trends clearly

### Analytics & Reports
- **Functionality**: Visual charts showing deployment trends, success rates over time, agent performance comparison, average duration by component, and stage-by-stage pipeline metrics
- **Purpose**: Enable data-driven decision making and identify patterns in deployment behavior
- **Trigger**: Navigate to Analytics from sidebar or click on chart widgets in dashboard
- **Progression**: Navigate to page → View deployment trends chart → Compare agent performance → Analyze duration by component → Export report data
- **Success criteria**: Charts render smoothly, data is accurate and current, export functionality works, filters apply to all visualizations

### Settings & Preferences
- **Functionality**: Configure refresh interval, notification preferences, dashboard layout, data retention period, alert thresholds, and view timezone information with real-time São Paulo time display
- **Purpose**: Personalize dashboard experience, control system behavior, and verify timezone configuration
- **Trigger**: Click Settings icon in sidebar
- **Progression**: Navigate to settings → View timezone status and current São Paulo time → Adjust preferences → Save configuration → See changes applied immediately
- **Success criteria**: Settings persist between sessions, changes apply in real-time, validation prevents invalid configurations, timezone section displays current São Paulo time with sample formats

### Export & Reporting
- **Functionality**: Export deploy history, agent sessions, and pipeline data to CSV/JSON formats with date range selection
- **Purpose**: Enable external analysis and compliance reporting
- **Trigger**: Click Export button in relevant pages
- **Progression**: Click export → Select format and date range → Download file → Use data externally
- **Success criteria**: Files download successfully, data format is correct, all filtered data is included

### Search & Filtering
- **Functionality**: Global search across all deploys, agents, and workflows with advanced filter options
- **Purpose**: Quickly find specific deployments or patterns in historical data
- **Trigger**: Click search icon or use keyboard shortcut (Ctrl/Cmd + K)
- **Progression**: Open search → Type query → View filtered results → Click result to navigate → Clear search to reset
- **Success criteria**: Search is instant, results are relevant, filters combine logically, keyboard navigation works

### Deploy History
- **Functionality**: Tabular view of deployment history with sortable columns and filters for date, component, status, and duration
- **Purpose**: Enable audit trail analysis and troubleshooting of deployment patterns
- **Trigger**: Click "Deploy History" in sidebar navigation
- **Progression**: Navigate to page → View chronological deploy list → Apply filters to narrow results → Sort by column → Review specific deploy details
- **Success criteria**: Table loads with all historical deploys, filters apply instantly, sorting works on all columns, data refreshes automatically

### Agent Activity
- **Functionality**: Timeline visualization of agent sessions, recent activity log, and lessons learned documentation
- **Purpose**: Track which AI agents (Claude/Copilot) are active and learn from deployment patterns
- **Trigger**: Click "Agent Activity" in sidebar navigation
- **Progression**: Navigate to page → View agent timeline → Review recent sessions → Read lessons learned insights → Identify agent usage patterns
- **Success criteria**: Timeline clearly shows agent transitions, sessions display relevant metadata, lessons learned are actionable

### Workflows Monitor
- **Functionality**: Display GitHub Actions workflows with their current status and last run information
- **Purpose**: Monitor CI/CD pipeline health at the workflow level
- **Trigger**: Click "Workflows" in sidebar navigation
- **Progression**: Navigate to page → View workflow list → Check status indicators → Identify failed/running workflows → Take corrective action
- **Success criteria**: All workflows listed with accurate status, status updates in real-time, visual hierarchy emphasizes issues

### Pipeline Monitor
- **Functionality**: Visual representation of the 7 deploy stages (Setup, Session Guard, Apply & Push, CI Gate, Promote, Save State, Audit) with status for each
- **Purpose**: Provide detailed visibility into where deploys are in the pipeline and where failures occur
- **Trigger**: Click "Pipeline Monitor" in sidebar navigation
- **Progression**: Navigate to page → View pipeline stages linearly → Identify current stage → Check for stage failures → Drill into stage details
- **Success criteria**: All 7 stages visible, current stage highlighted, failures clearly marked, progression arrows show flow

### Auto-Refresh System
- **Functionality**: Automatically fetch updated data from /api/state endpoint every 30 seconds with real-time timezone conversion
- **Purpose**: Keep dashboard current without manual intervention, displaying all times in São Paulo timezone
- **Trigger**: Automatic on app load, runs continuously
- **Progression**: App loads → Initial data fetch → Timezone conversion applied → 30s timer starts → Data refreshes → Timezone conversion reapplied → UI updates → Timer resets
- **Success criteria**: Data refreshes seamlessly without disrupting user interaction, timestamp shows last update, all dates displayed in São Paulo timezone (GMT-3)

### Real-Time Timezone Conversion
- **Functionality**: Automatically converts all API timestamps to São Paulo timezone (America/Sao_Paulo, GMT-3) as data is fetched, with visual indicators showing timezone status
- **Purpose**: Ensure all dates and times throughout the dashboard are displayed in the local Brazilian timezone for accurate monitoring
- **Trigger**: Runs automatically on every API data fetch and refresh
- **Progression**: API data received → All timestamp fields identified → Converted to São Paulo timezone → Data stored in state → Components display formatted dates → Visual indicator confirms timezone
- **Success criteria**: All dates throughout app display in São Paulo time, relative times in Portuguese, timezone indicator visible in sidebar, Settings page shows current São Paulo time with sample formats

## Edge Case Handling

- **API Unavailable**: Display cached data with warning indicator that live updates are unavailable
- **Malformed JSON**: Show error state with option to retry, preserve previous valid state
- **Empty State**: When no deploys exist, show helpful empty state with setup instructions
- **Long-Running Deploys**: Handle deploys exceeding expected duration with special indicator
- **Concurrent Agent Activity**: Display overlapping agent sessions without visual collision
- **Filter No Results**: Show clear "no results" message with option to clear filters
- **Large Datasets**: Implement pagination or virtual scrolling for tables with 100+ rows
- **Invalid Timestamps**: Gracefully handle malformed date strings from API, show placeholder or skip conversion
- **Timezone Conversion Errors**: Fall back to raw timestamp display if conversion fails, log error to console
- **DST Transitions**: Correctly handle daylight saving time changes in São Paulo timezone

## Design Direction

The design should evoke feelings of technical confidence, operational control, and clarity. Users should feel they have comprehensive visibility into their CI/CD operations with a professional, terminal-inspired aesthetic that appeals to DevOps engineers.

## Color Selection

A dark, sophisticated palette inspired by modern developer tools and terminal interfaces.

- **Primary Color**: Electric Blue `oklch(0.65 0.19 245)` - Communicates technology, trust, and active systems
- **Secondary Colors**: 
  - Deep Charcoal `oklch(0.18 0.01 240)` for primary surfaces
  - Slate Gray `oklch(0.25 0.01 240)` for card backgrounds
  - Soft Gray `oklch(0.35 0.01 240)` for borders and dividers
- **Accent Color**: Cyan `oklch(0.75 0.15 200)` - Highlights active elements and calls attention to running states
- **Status Colors**:
  - Success: Vibrant Green `oklch(0.70 0.18 145)` 
  - Failed: Alert Red `oklch(0.60 0.22 25)`
  - Running: Amber Yellow `oklch(0.75 0.15 75)`
  - Idle: Neutral Gray `oklch(0.55 0.02 240)`

- **Foreground/Background Pairings**:
  - Primary (Electric Blue): White text `oklch(0.98 0 0)` - Ratio 7.2:1 ✓
  - Success (Vibrant Green): White text `oklch(0.98 0 0)` - Ratio 6.8:1 ✓
  - Failed (Alert Red): White text `oklch(0.98 0 0)` - Ratio 5.1:1 ✓
  - Running (Amber): Dark text `oklch(0.15 0 0)` - Ratio 8.5:1 ✓
  - Background (Deep Charcoal): Light Gray text `oklch(0.88 0.01 240)` - Ratio 9.2:1 ✓

## Font Selection

Typefaces should convey technical precision and modern sophistication, balancing readability with a developer-focused aesthetic.

- **Primary**: Space Grotesk - Modern, technical feel with excellent readability for UI text
- **Monospace**: JetBrains Mono - For version numbers, timestamps, and code-like elements

- **Typographic Hierarchy**:
  - H1 (Page Titles): Space Grotesk Bold/32px/tight letter spacing (-0.02em)
  - H2 (Section Headers): Space Grotesk Semibold/24px/normal spacing
  - H3 (Card Titles): Space Grotesk Medium/18px/normal spacing
  - Body (General UI): Space Grotesk Regular/15px/relaxed line height (1.6)
  - Mono (Data Values): JetBrains Mono Regular/14px/normal spacing
  - Small (Timestamps, Meta): Space Grotesk Regular/13px/normal spacing

## Animations

Animations should reinforce system activity and state changes with subtle, purposeful motion. Use smooth transitions for status changes (300ms ease-out) to draw attention to updates. Implement pulse animation on "running" status indicators to show activity. Page transitions should be minimal (200ms fade) to maintain professional feel. Avoid excessive motion that could distract from monitoring tasks.

## Component Selection

- **Components**:
  - Sidebar: Full-height navigation with icon + label format using shadcn Sidebar component
  - Card: Metric display containers using shadcn Card with customized dark styling
  - Table: Deploy history and workflows using shadcn Table with sorting capabilities
  - Badge: Status indicators using shadcn Badge with custom color variants
  - Tabs: Section switching within pages using shadcn Tabs
  - ScrollArea: For long lists using shadcn ScrollArea
  - Separator: Visual dividers using shadcn Separator
  
- **Customizations**:
  - Custom timeline component for agent activity (vertical timeline with connection lines)
  - Custom pipeline stage visualizer (horizontal step indicator with arrows)
  - Status badge variants for success/failed/running/idle states
  - Metric card component with large value display and trend indicators

- **States**:
  - Buttons: Subtle hover with blue glow effect, active state with darker background
  - Table rows: Hover with slight background lightening, selected row highlighted
  - Status badges: Pulse animation on "running" state, static for others
  - Cards: Subtle elevation on hover, border highlight for interactive cards
  - Sidebar items: Active page highlighted with blue accent bar and background

- **Icon Selection**:
  - Dashboard: ChartBar (overview metrics)
  - Deploy History: ClockCounterClockwise (historical records)
  - Agent Activity: Robot (AI agents)
  - Workflows: GitBranch (GitHub Actions)
  - Pipeline Monitor: Pipeline (stages visualization)
  - Refresh: ArrowsClockwise (auto-refresh indicator)
  - Status: CheckCircle (success), XCircle (failed), Clock (running), MinusCircle (idle)
  - Timezone: Globe (timezone indicator and settings)

- **Spacing**:
  - Page padding: p-6 (24px)
  - Card padding: p-6 (24px)
  - Card gaps: gap-6 (24px)
  - Section spacing: space-y-8 (32px)
  - Tight groupings: gap-3 (12px)
  - Table cell padding: px-4 py-3

- **Mobile**:
  - Sidebar collapses to icon-only drawer on <768px
  - Cards stack vertically on mobile
  - Tables scroll horizontally with fixed first column
  - Reduce font sizes by 1-2px on mobile
  - Pipeline stage visualization scrolls horizontally
  - Increase touch targets to minimum 44px
