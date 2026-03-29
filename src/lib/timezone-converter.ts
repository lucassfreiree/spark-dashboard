import { DashboardState } from '@/types/dashboard'

export function convertApiDataToSaoPauloTimezone(data: any): DashboardState {
  const converted = { ...data }

  if (converted.lastDeploy?.date) {
    converted.lastDeploy = {
      ...converted.lastDeploy,
      date: new Date(converted.lastDeploy.date).toISOString()
    }
  }

  if (converted.lastUpdated) {
    converted.lastUpdated = new Date(converted.lastUpdated).toISOString()
  }

  if (converted.deployHistory) {
    converted.deployHistory = converted.deployHistory.map((deploy: any) => ({
      ...deploy,
      date: new Date(deploy.date).toISOString()
    }))
  }

  if (converted.agentActivity) {
    if (converted.agentActivity.timeline) {
      converted.agentActivity.timeline = converted.agentActivity.timeline.map((event: any) => ({
        ...event,
        timestamp: new Date(event.timestamp).toISOString()
      }))
    }

    if (converted.agentActivity.recentSessions) {
      converted.agentActivity.recentSessions = converted.agentActivity.recentSessions.map((session: any) => ({
        ...session,
        startTime: new Date(session.startTime).toISOString(),
        endTime: session.endTime ? new Date(session.endTime).toISOString() : undefined
      }))
    }

    if (converted.agentActivity.lessonsLearned) {
      converted.agentActivity.lessonsLearned = converted.agentActivity.lessonsLearned.map((lesson: any) => ({
        ...lesson,
        date: typeof lesson.date === 'string' && lesson.date.match(/^\d{4}-\d{2}-\d{2}/)
          ? new Date(lesson.date).toISOString()
          : lesson.date
      }))
    }
  }

  if (converted.workflows) {
    converted.workflows = converted.workflows.map((workflow: any) => ({
      ...workflow,
      lastRun: new Date(workflow.lastRun).toISOString()
    }))
  }

  if (converted.pipeline?.stages) {
    converted.pipeline.stages = converted.pipeline.stages.map((stage: any) => ({
      ...stage,
      startTime: stage.startTime ? new Date(stage.startTime).toISOString() : undefined,
      endTime: stage.endTime ? new Date(stage.endTime).toISOString() : undefined
    }))
  }

  return converted as DashboardState
}
