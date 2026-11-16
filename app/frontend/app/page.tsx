"use client";

import { useCallback, useEffect, useState } from "react";
import InvoiceForm from "./components/InvoiceForm";
import InvoiceList from "./components/InvoiceList";
import {
  createInvoice,
  Invoice,
  InvoiceInput,
  listInvoices,
} from "./components/api";

export default function Home() {
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      setInvoices(await listInvoices());
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }, []);

  useEffect(() => {
    refresh().finally(() => setLoading(false));
  }, [refresh]);

  async function handleCreate(input: InvoiceInput) {
    try {
      await createInvoice(input);
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    }
  }

  return (
    <main className="mx-auto flex w-full max-w-4xl flex-1 flex-col gap-6 px-4 py-12">
      <h1 className="text-3xl font-semibold tracking-tight text-black dark:text-white">
        Invoice tracker
      </h1>

      {error && (
        <p className="rounded-lg border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-700 dark:border-red-900 dark:bg-red-950 dark:text-red-300">
          {error}
        </p>
      )}

      <InvoiceForm onSave={handleCreate} />

      {loading ? (
        <p className="text-sm text-zinc-500">Loading invoices…</p>
      ) : (
        <InvoiceList invoices={invoices} />
      )}
    </main>
  );
}
