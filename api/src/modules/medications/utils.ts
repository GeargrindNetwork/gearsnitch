import type { IMedicationDose } from '../../models/MedicationDose.js';

export interface MedicationDoseSummaryInput {
  category: IMedicationDose['category'];
  doseMg: number | null | undefined;
}

export interface MedicationOverlaySummary {
  entryCount: number;
  totalDoseMg: number;
  categoryDoseMg: {
    steroid: number;
    peptide: number;
    oralMedication: number;
  };
  hasMedication: boolean;
}

export function dateKeyFromDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function dayOfYearFromDateKey(dateKey: string): number {
  const [year, month, day] = dateKey.split('-').map((value) => parseInt(value, 10));
  const current = Date.UTC(year, month - 1, day);
  const start = Date.UTC(year, 0, 0);
  return Math.floor((current - start) / 86_400_000);
}

export function normalizeDoseToMg(value: number, unit: string): number | null {
  if (!Number.isFinite(value) || value < 0) {
    return null;
  }

  if (unit === 'mg') {
    return value;
  }

  if (unit === 'mcg') {
    return value / 1000;
  }

  return null;
}

export function emptyMedicationOverlay(): MedicationOverlaySummary {
  return {
    entryCount: 0,
    totalDoseMg: 0,
    categoryDoseMg: {
      steroid: 0,
      peptide: 0,
      oralMedication: 0,
    },
    hasMedication: false,
  };
}

export function summarizeMedicationDoses(
  doses: MedicationDoseSummaryInput[],
): MedicationOverlaySummary {
  const summary = emptyMedicationOverlay();

  for (const dose of doses) {
    summary.entryCount += 1;

    if (typeof dose.doseMg === 'number' && Number.isFinite(dose.doseMg) && dose.doseMg >= 0) {
      summary.totalDoseMg += dose.doseMg;
      summary.categoryDoseMg[dose.category] += dose.doseMg;
    }
  }

  summary.hasMedication = summary.entryCount > 0;
  return summary;
}
