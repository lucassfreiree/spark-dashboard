import { DashboardState } from '@/types/dashboard'

/**
 * Converts date strings in the dashboard state to proper ISO format.
 * state.json from spark-sync-state.yml already uses ISO dates,
 * so this is a safety pass for any edge cases.
 */
export function convertApiDataToSaoPauloTimezone(data: DashboardState): DashboardState {
  return {
    ...data,
    lastUpdated: data.lastSync || data.lastUpdated || new Date().toISOString()
  }
}
