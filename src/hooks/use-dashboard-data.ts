import { useState, useEffect } from 'react'
import { DashboardState } from '@/types/dashboard'
import { mockDashboardData } from '@/lib/mockData'
import { convertApiDataToSaoPauloTimezone } from '@/lib/timezone-converter'

const REFRESH_INTERVAL = 30000

export function useDashboardData() {
  const [data, setData] = useState<DashboardState>(mockDashboardData)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchData = async () => {
    try {
      setIsLoading(true)
      setError(null)
      
      const response = await fetch('/api/state')
      
      if (!response.ok) {
        throw new Error('Failed to fetch data')
      }
      
      const jsonData = await response.json()
      const convertedData = convertApiDataToSaoPauloTimezone({
        ...jsonData,
        lastUpdated: new Date().toISOString()
      })
      setData(convertedData)
    } catch (err) {
      console.error('Error fetching dashboard data:', err)
      setError('Using cached data - live updates unavailable')
      setData(prev => ({
        ...prev,
        lastUpdated: new Date().toISOString()
      }))
    } finally {
      setIsLoading(false)
    }
  }

  useEffect(() => {
    fetchData()

    const interval = setInterval(() => {
      fetchData()
    }, REFRESH_INTERVAL)

    return () => clearInterval(interval)
  }, [])

  return { data, isLoading, error, refetch: fetchData }
}
