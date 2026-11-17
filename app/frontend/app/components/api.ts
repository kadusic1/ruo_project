export const API_URL = process.env.NEXT_PUBLIC_API_URL || "/api";

export const STATUSES = ["draft", "sent", "paid"] as const;
export type Status = (typeof STATUSES)[number];

export type Invoice = {
  id: number;
  number: string;
  client: string;
  amount: number;
  status: Status;
  due_date: string | null;
  created_at: string | null;
};

export type InvoiceInput = {
  number: string;
  client: string;
  amount: number;
  status: Status;
  due_date: string | null;
};

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    ...init,
    headers: init?.body ? { "Content-Type": "application/json" } : undefined,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API ${res.status}: ${text}`);
  }
  return res.status === 204 ? (undefined as T) : res.json();
}

export function listInvoices(): Promise<Invoice[]> {
  return request<Invoice[]>("/invoices");
}

export function createInvoice(invoice: InvoiceInput): Promise<Invoice> {
  return request<Invoice>("/invoices", {
    method: "POST",
    body: JSON.stringify(invoice),
  });
}
