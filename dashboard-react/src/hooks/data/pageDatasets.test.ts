import { describe, it, expect } from 'vitest';
import { SHELL_CORE, PAGE_DATASETS } from './pageDatasets';
import { DATASET_LOADERS } from '../useCubeData';
import type { DatasetName } from './datasetTypes';

describe('pageDatasets', () => {
  it('every dataset referenced has a loader in DATASET_LOADERS', () => {
    const all = new Set<DatasetName>([...SHELL_CORE, ...Object.values(PAGE_DATASETS).flat()]);
    for (const name of all) {
      expect(DATASET_LOADERS[name], `missing loader for ${name}`).toBeTypeOf('function');
    }
  });
  it('SHELL_CORE holds exactly what the shell reads', () => {
    expect([...SHELL_CORE].sort()).toEqual(
      ['actions', 'cubeMeta', 'dataFreshness', 'peak', 'sqp_weekly', 'weekly_trends'].sort()
    );
  });
  it('API-only pages have no cube datasets', () => {
    expect(PAGE_DATASETS.admin).toEqual([]);
    expect(PAGE_DATASETS.alerts).toEqual([]);
    expect(PAGE_DATASETS.research).toEqual([]);
  });
  it('ads page requests the weekly term trend dataset', () => {
    expect(PAGE_DATASETS.ads).toContain('campaign_search_terms_weekly');
  });
});
