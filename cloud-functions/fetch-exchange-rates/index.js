/**
 * Cloud Function to fetch real-time currency exchange rates for ILS, USD, HKD
 * Returns current market rates from exchangerate-api.com
 */

const https = require('https');

// Exchange rate API configuration
const API_URL = 'https://api.exchangerate-api.com/v4/latest/USD';
const CURRENCIES = ['ILS', 'USD', 'HKD'];
const TIMEOUT_MS = 15000; // 15 seconds

/**
 * Fetch exchange rates from exchangerate-api.com
 */
async function fetchExchangeRates() {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error('API request timeout after 15 seconds'));
    }, TIMEOUT_MS);

    https.get(API_URL, (res) => {
      // Check HTTP status code
      if (res.statusCode !== 200) {
        clearTimeout(timeout);
        reject(new Error(`API returned status code ${res.statusCode}`));
        return;
      }

      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        clearTimeout(timeout);
        try {
          const response = JSON.parse(data);

          // exchangerate-api.com v4 returns: { base, date, rates: {...} }
          if (response.rates && typeof response.rates === 'object') {
            resolve({
              success: true,
              timestamp: new Date().toISOString(),
              api_timestamp: response.date ? `${response.date}T00:00:00Z` : new Date().toISOString(),
              base_currency: response.base || 'USD',
              rates: response.rates,
              provider: 'exchangerate-api.com'
            });
          } else {
            reject(new Error('API returned error or no rates data'));
          }
        } catch (error) {
          reject(new Error(`Failed to parse API response: ${error.message}`));
        }
      });
    }).on('error', (error) => {
      clearTimeout(timeout);
      reject(new Error(`API request failed: ${error.message}`));
    });
  });
}

/**
 * Generate all currency pair combinations from API rates
 */
function generateCurrencyPairs(rates) {
  const pairs = [];

  // Extract rates for our currencies
  const usdToIls = rates.ILS || 3.822;
  const usdToHkd = rates.HKD || 7.812;
  const usdToUsd = 1.0;

  // USD as base currency
  pairs.push({
    base_currency: 'USD',
    target_currency: 'ILS',
    exchange_rate: usdToIls,
    inverse_rate: 1 / usdToIls
  });

  pairs.push({
    base_currency: 'USD',
    target_currency: 'HKD',
    exchange_rate: usdToHkd,
    inverse_rate: 1 / usdToHkd
  });

  pairs.push({
    base_currency: 'USD',
    target_currency: 'USD',
    exchange_rate: usdToUsd,
    inverse_rate: 1.0
  });

  // ILS as base currency
  pairs.push({
    base_currency: 'ILS',
    target_currency: 'USD',
    exchange_rate: 1 / usdToIls,
    inverse_rate: usdToIls
  });

  pairs.push({
    base_currency: 'ILS',
    target_currency: 'HKD',
    exchange_rate: usdToHkd / usdToIls,
    inverse_rate: usdToIls / usdToHkd
  });

  pairs.push({
    base_currency: 'ILS',
    target_currency: 'ILS',
    exchange_rate: 1.0,
    inverse_rate: 1.0
  });

  // HKD as base currency
  pairs.push({
    base_currency: 'HKD',
    target_currency: 'USD',
    exchange_rate: 1 / usdToHkd,
    inverse_rate: usdToHkd
  });

  pairs.push({
    base_currency: 'HKD',
    target_currency: 'ILS',
    exchange_rate: usdToIls / usdToHkd,
    inverse_rate: usdToHkd / usdToIls
  });

  pairs.push({
    base_currency: 'HKD',
    target_currency: 'HKD',
    exchange_rate: 1.0,
    inverse_rate: 1.0
  });

  return pairs;
}

/**
 * Cloud Function entry point
 */
exports.fetchExchangeRates = async (req, res) => {
  console.log('=== Function called ===');
  console.log('Method:', req.method);
  console.log('URL:', req.url);
  
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    console.log('Handling OPTIONS preflight request');
    res.status(204).send('');
    return;
  }

  try {
    console.log('Fetching real-time exchange rates from API...');
    console.log('API URL:', API_URL);

    // Fetch rates from external API
    const apiData = await fetchExchangeRates();
    console.log('API data received:', JSON.stringify(apiData).substring(0, 200) + '...');

    // Generate all currency pairs
    const currencyPairs = generateCurrencyPairs(apiData.rates);
    console.log(`Generated ${currencyPairs.length} currency pairs`);

    // Prepare response data
    const responseData = {
      success: true,
      timestamp: apiData.timestamp,
      api_timestamp: apiData.api_timestamp,
      base_currency: 'USD',
      rates: currencyPairs,
      metadata: {
        api_provider: apiData.provider,
        requested_currencies: CURRENCIES,
        total_pairs: currencyPairs.length,
        quality_score: 100,
        note: 'Real-time exchange rates from live API'
      }
    };

    console.log(`✅ Successfully fetched ${currencyPairs.length} currency pairs`);
    console.log(`USD→ILS: ${currencyPairs.find(p => p.base_currency === 'USD' && p.target_currency === 'ILS')?.exchange_rate}`);
    console.log(`USD→HKD: ${currencyPairs.find(p => p.base_currency === 'USD' && p.target_currency === 'HKD')?.exchange_rate}`);

    // Check if this is a BigQuery remote function call
    // BigQuery sends requests with "calls" field in the body
    const isBigQueryCall = req.body && Array.isArray(req.body.calls);
    
    if (isBigQueryCall) {
      // Format response for BigQuery remote function
      // BigQuery expects: { "replies": [...] }
      const response = {
        replies: [responseData]
      };
      res.status(200).json(response);
    } else {
      // Direct HTTP call - return data directly
      res.status(200).json(responseData);
    }

  } catch (error) {
    console.error('❌ Error fetching exchange rates:', error);
    console.error('Error stack:', error.stack);
    console.error('Error message:', error.message);

    // Return error response - no fallback data allowed
    const errorData = {
      success: false,
      error: error.message,
      timestamp: new Date().toISOString(),
      rates: [], // Empty array - no fallback data
      metadata: {
        api_provider: 'ERROR',
        quality_score: 0,
        note: `API call failed: ${error.message}. No fallback data provided.`
      }
    };

    // Check if this is a BigQuery remote function call
    const isBigQueryCall = req.body && Array.isArray(req.body.calls);
    
    if (isBigQueryCall) {
      // Format error response for BigQuery remote function
      const errorResponse = {
        replies: [errorData]
      };
      console.log('Sending error response (BigQuery format):', JSON.stringify(errorResponse));
      res.status(200).json(errorResponse); // BigQuery expects 200 even for errors
    } else {
      console.log('Sending error response (direct HTTP):', JSON.stringify(errorData));
      res.status(500).json(errorData); // Direct HTTP calls get 500 error
    }
  }
};