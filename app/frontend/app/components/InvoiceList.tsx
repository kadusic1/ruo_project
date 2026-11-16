"use client";

import { Invoice } from "./api";

type Props = {
  invoices: Invoice[];
};

const statusStyles: Record<string, string> = {
  draft: "bg-zinc-100 text-zinc-700 dark:bg-zinc-800 dark:text-zinc-300",
  sent: "bg-blue-100 text-blue-700 dark:bg-blue-950 dark:text-blue-300",
  paid: "bg-green-100 text-green-700 dark:bg-green-950 dark:text-green-300",
};

export default function InvoiceList({ invoices }: Props) {
  return (
    <div className="overflow-x-auto rounded-xl border border-zinc-200 bg-white shadow-sm dark:border-zinc-800 dark:bg-zinc-950">
      <table className="w-full text-left text-sm text-black dark:text-white">
        <thead className="border-b border-zinc-200 text-xs uppercase tracking-wide text-zinc-500 dark:border-zinc-800 dark:text-zinc-400">
          <tr>
            <th className="px-4 py-3">Number</th>
            <th className="px-4 py-3">Client</th>
            <th className="px-4 py-3">Amount</th>
            <th className="px-4 py-3">Status</th>
            <th className="px-4 py-3">Due date</th>
          </tr>
        </thead>
        <tbody>
          {invoices.map((invoice) => (
            <tr
              key={invoice.id}
              className="border-b border-zinc-100 last:border-0 dark:border-zinc-900"
            >
              <td className="px-4 py-3 font-medium">{invoice.number}</td>
              <td className="px-4 py-3">{invoice.client}</td>
              <td className="px-4 py-3 tabular-nums">
                {invoice.amount.toFixed(2)}
              </td>
              <td className="px-4 py-3">
                <span
                  className={`rounded-full px-2 py-0.5 text-xs font-medium capitalize ${
                    statusStyles[invoice.status] ?? statusStyles.draft
                  }`}
                >
                  {invoice.status}
                </span>
              </td>
              <td className="px-4 py-3">{invoice.due_date?.slice(0, 10) ?? "—"}</td>
            </tr>
          ))}
          {invoices.length === 0 && (
            <tr>
              <td colSpan={5} className="px-4 py-10 text-center text-zinc-500">
                No invoices yet — add one above.
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}
