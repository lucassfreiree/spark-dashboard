export interface UserSettings {
  refreshInterval: number
  enableNotifications: boolean
  notifyOnFailure: boolean
  notifyOnSuccess: boolean
  dataRetentionDays: number
  dashboardLayout: 'compact' | 'comfortable' | 'spacious'
  theme: 'dark' | 'light' | 'system'
  alertThresholds: {
    failureRate: number
    longRunningDeploy: number
  }
}

export const defaultSettings: UserSettings = {
  refreshInterval: 30000,
  enableNotifications: true,
  notifyOnFailure: true,
  notifyOnSuccess: false,
  dataRetentionDays: 30,
  dashboardLayout: 'comfortable',
  theme: 'dark',
  alertThresholds: {
    failureRate: 20,
    longRunningDeploy: 600000
  }
}
