"use client";

import { FormEvent, useState } from "react";
import { InvoiceInput, STATUSES } from "./api";

type Props = {
  onSave: (input: InvoiceInput) => Promise<void>;
};

export default function InvoiceForm({ onSave }: Props) {
  const [number, setNumber] = useState("");
  const [client, setClient] = useState("");
  const [amount, setAmount] = useState("");
  const [status, setStatus] = useState<string>("draft");
  const [dueDate, setDueDate] = useState("");
  const [saving, setSaving] = useState(false);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    try {
      await onSave({
        number,
        client,
        amount: Number(amount) || 0,
        status: status as InvoiceInput["status"],
        due_date: dueDate || null,
      });
      setNumber("");
      setClient("");
      setAmount("");
      setStatus("draft");
      setDueDate("");
    } finally {
      setSaving(false);
    }
  }

  const label = "block text-sm font-medium text-zinc-700 dark:text-zinc-300";
  const field =
    "mt-1 w-full rounded-md border border-zinc-300 bg-white px-3 py-2 text-sm text-black focus:border-zinc-500 focus:outline-none dark:border-zinc-700 dark:bg-zinc-900 dark:text-white";

  return (
    <form
      onSubmit={handleSubmit}
      className="grid grid-cols-1 gap-4 rounded-xl border border-zinc-200 bg-white p-6 shadow-sm dark:border-zinc-800 dark:bg-zinc-950 sm:grid-cols-2 lg:grid-cols-5"
    >
      <div className="lg:col-span-1">
        <label htmlFor="number" className={label}>
          Number
        </label>
        <input
          id="number"
          className={field}
          value={number}
          onChange={(e) => setNumber(e.target.value)}
          placeholder="INV-001"
          required
        />
      </div>

      <div className="lg:col-span-1">
        <label htmlFor="client" className={label}>
          Client
        </label>
        <input
          id="client"
          className={field}
          value={client}
          onChange={(e) => setClient(e.target.value)}
          placeholder="Acme Inc."
          required
        />
      </div>

      <div className="lg:col-span-1">
        <label htmlFor="amount" className={label}>
          Amount
        </label>
        <input
          id="amount"
          className={field}
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          type="number"
          step="0.01"
          min="0"
          placeholder="0.00"
          required
        />
      </div>

      <div className="lg:col-span-1">
        <label htmlFor="status" className={label}>
          Status
        </label>
        <select
          id="status"
          className={field}
          value={status}
          onChange={(e) => setStatus(e.target.value)}
        >
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
      </div>

      <div className="lg:col-span-1">
        <label htmlFor="due" className={label}>
          Due date
        </label>
        <input
          id="due"
          className={field}
          value={dueDate}
          onChange={(e) => setDueDate(e.target.value)}
          type="date"
        />
      </div>

      <div className="flex items-center gap-2 sm:col-span-2 lg:col-span-5">
        <button
          type="submit"
          disabled={saving}
          className="rounded-full bg-zinc-900 px-5 py-2 text-sm font-medium text-white transition-colors hover:bg-zinc-700 disabled:opacity-50 dark:bg-white dark:text-black dark:hover:bg-zinc-300"
        >
          Add invoice
        </button>
      </div>
    </form>
  );
}
