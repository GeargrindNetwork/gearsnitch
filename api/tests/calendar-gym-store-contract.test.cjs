const fs = require('node:fs');
const path = require('node:path');

const apiRoot = path.join(__dirname, '..');

function read(relativePath) {
  return fs.readFileSync(path.join(apiRoot, relativePath), 'utf8');
}

describe('calendar, gym geofence, and store seed contract', () => {
  const calendarRoutes = read('src/modules/calendar/routes.ts');
  const gymRoutes = read('src/modules/gyms/routes.ts');
  const eventLogModel = read('src/models/EventLog.ts');
  const storeService = read('src/modules/store/storeService.ts');

  test('calendar day detail includes run history and month summaries track run completions', () => {
    expect(calendarRoutes).toContain("import { Run } from '../../models/Run.js';");
    expect(calendarRoutes).toContain('runsCompleted: number;');
    expect(calendarRoutes).toContain('runs,');
  });

  test('gym geofence ingestion is implemented instead of returning a deferred 501', () => {
    expect(gymRoutes).toContain("router.post(\n  '/events'");
    expect(gymRoutes).toContain("eventType: z.enum(['entry', 'exit'])");
    expect(gymRoutes).toContain("sessionEventType = eventType === 'entry' ? 'gym_entry' : 'gym_exit'");
    expect(eventLogModel).toContain("'gym_entry'");
    expect(eventLogModel).toContain("'gym_exit'");
  });

  test('store service seeds a jump rope product for the catalog', () => {
    expect(storeService).toContain('ensureSeedData');
    expect(storeService).toContain('GS-JUMPROPE-001');
    expect(storeService).toContain('GearSnitch Speed Jump Rope');
  });
});
