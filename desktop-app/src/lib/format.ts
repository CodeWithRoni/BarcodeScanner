const FORMAT_LABELS: Record<string, string> = {
  qr_code: "QR",
  qrcode: "QR",
  qr: "QR",
  data_matrix: "DataMatrix",
  datamatrix: "DataMatrix",
  ean13: "EAN-13",
  ean_13: "EAN-13",
  ean8: "EAN-8",
  ean_8: "EAN-8",
  upc_a: "UPC-A",
  upca: "UPC-A",
  upc_e: "UPC-E",
  upce: "UPC-E",
  code128: "Code 128",
  code_128: "Code 128",
  code39: "Code 39",
  code_39: "Code 39",
  code93: "Code 93",
  code_93: "Code 93",
  itf: "ITF",
  itf14: "ITF-14",
  codabar: "Codabar",
  pdf417: "PDF417",
  aztec: "Aztec",
  unknown: "Unknown",
};

export function formatLabel(format: string): string {
  const key = format.toLowerCase().replace(/[\s-]/g, "_");
  return FORMAT_LABELS[key] ?? FORMAT_LABELS[key.replace(/_/g, "")] ?? format.toUpperCase();
}

export function isTwoD(format: string): boolean {
  return ["QR", "DataMatrix", "PDF417", "Aztec"].includes(formatLabel(format));
}

export function timeAgo(ms: number, now = Date.now()): string {
  const diff = Math.max(0, Math.round((now - ms) / 1000));
  if (diff < 5) return "just now";
  if (diff < 60) return `${diff}s ago`;
  const min = Math.round(diff / 60);
  if (min < 60) return `${min}m ago`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr}h ago`;
  return new Date(ms).toLocaleDateString();
}

export function clockTime(ms: number): string {
  return new Date(ms).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

export function duration(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s % 60}s`;
  return `${s}s`;
}

export function platformLabel(platform: string): string {
  switch (platform.toLowerCase()) {
    case "android":
      return "Android";
    case "ios":
      return "iOS";
    case "windows":
      return "Windows";
    case "macos":
      return "macOS";
    case "linux":
      return "Linux";
    default:
      return platform || "Unknown";
  }
}
