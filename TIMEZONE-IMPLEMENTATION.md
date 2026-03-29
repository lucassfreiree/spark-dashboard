# Real-Time Timezone Conversion for API Data

## Overview
This dashboard automatically converts all API timestamps to São Paulo timezone (America/Sao_Paulo, GMT-3) in real-time as data is fetched.

## Implementation Details

### Key Components

#### 1. **Timezone Utility Functions** (`src/lib/utils.ts`)
- `convertToSaoPauloTime(date)`: Converts any date to São Paulo timezone
- `formatDateSaoPaulo(date, format)`: Formats dates in São Paulo timezone with custom format strings
- `formatDistanceToNowSaoPaulo(date, options)`: Shows relative time ("X minutes ago") in São Paulo timezone

#### 2. **API Data Converter** (`src/lib/timezone-converter.ts`)
- `convertApiDataToSaoPauloTimezone(data)`: Automatically processes all date fields in API responses
- Handles multiple data structures:
  - Deploy history dates
  - Agent activity timestamps
  - Workflow execution times
  - Pipeline stage times
  - Session start/end times

#### 3. **Data Fetching Hook** (`src/hooks/use-dashboard-data.ts`)
- Automatically applies timezone conversion when API data is fetched
- Ensures all dates throughout the app are in São Paulo timezone
- Runs every 30 seconds to keep data fresh

## Usage

### Displaying Dates
All date formatting should use the utility functions from `@/lib/utils`:

```tsx
import { formatDateSaoPaulo, formatDistanceToNowSaoPaulo } from '@/lib/utils'

// Full date and time
{formatDateSaoPaulo(deploy.date, 'dd/MM/yyyy HH:mm:ss')}

// Short format
{formatDateSaoPaulo(deploy.date, 'dd/MM/yy HH:mm')}

// Time only
{formatDateSaoPaulo(stage.startTime, 'HH:mm:ss')}

// Relative time
{formatDistanceToNowSaoPaulo(event.timestamp, { addSuffix: true })}
```

### Supported Format Strings
Using date-fns format tokens:
- `dd/MM/yyyy` - 15/01/2024
- `HH:mm:ss` - 14:32:00
- `dd/MM/yy HH:mm` - 15/01/24 14:32
- `PPpp` - 15 de janeiro de 2024 às 14:32:00

## Features

### ✅ Automatic Conversion
- All API timestamps converted on fetch
- No manual conversion needed in components
- Consistent timezone across entire app

### ✅ Real-Time Updates
- Data refreshes every 30 seconds
- Timezone conversion applied to each refresh
- Visual indicator shows last update time

### ✅ Portuguese Locale
- Date formatting uses Portuguese (Brazil) locale
- Relative times in Portuguese (e.g., "há 5 minutos")

### ✅ Visual Indicators
- Sidebar shows timezone (GMT-3)
- Settings page displays current São Paulo time
- Sample formats shown for reference

## API Data Structure

All timestamp fields in API responses are automatically converted:

```typescript
interface DashboardState {
  lastDeploy: {
    date: string  // Converted to São Paulo timezone
  }
  deployHistory: [{
    date: string  // Converted
  }]
  agentActivity: {
    timeline: [{
      timestamp: string  // Converted
    }]
    recentSessions: [{
      startTime: string  // Converted
      endTime?: string   // Converted
    }]
  }
  workflows: [{
    lastRun: string  // Converted
  }]
  pipeline: {
    stages: [{
      startTime?: string  // Converted
      endTime?: string    // Converted
    }]
  }
}
```

## Testing Timezone Conversion

To verify timezone conversion is working:

1. Check the Settings page - it shows current São Paulo time with sample formats
2. Compare displayed times with UTC times from API (should be -3 hours)
3. Look for the timezone indicator (GMT-3) in the sidebar footer

## Troubleshooting

### Dates Showing Wrong Time
- Verify API is sending valid ISO 8601 timestamps
- Check browser console for conversion errors
- Ensure date-fns-tz is properly installed

### Relative Times Not in Portuguese
- Confirm ptBR locale is imported from date-fns
- Check formatDistanceToNowSaoPaulo includes locale option

### Timezone Not Converting
- Verify convertApiDataToSaoPauloTimezone is called in use-dashboard-data hook
- Check that timezone-converter handles all date fields in your data structure
