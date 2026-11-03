// Monthly cost budget with early warning (actual 80%) and forecast (100%) alerts.
targetScope = 'subscription'

@minValue(1)
param amount int
param contactEmails array
param startDate string

resource budget 'Microsoft.Consumption/budgets@2026-06-01' = {
  name: 'budget-matterhub-monthly'
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
    }
    notifications: {
      actual80: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: contactEmails
      }
      forecast100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: contactEmails
      }
    }
  }
}
