import { useRef, useEffect } from 'react';

/** Canvas sparkline with bezier curves, gradient fill, glow, dot on last point. */
export function SparklineCanvas({
  data,
  color,
  glow,
  width,
  height,
  padTop = 16,
  padBottom = 16,
  strokeWidth = 2.5,
  dotRadius = 5,
}: {
  data: number[];
  color: string;
  glow: string;
  width: number;
  height: number;
  padTop?: number;
  padBottom?: number;
  strokeWidth?: number;
  dotRadius?: number;
}) {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const c = ref.current;
    if (!c || !data.length) return;
    const dpr = window.devicePixelRatio || 1;
    c.width = width * dpr;
    c.height = height * dpr;
    const ctx = c.getContext('2d');
    if (!ctx) return;
    ctx.scale(dpr, dpr);

    const padL = 8;
    const padR = 8;
    const w = width - padL - padR;
    const h = height - padTop - padBottom;
    const min = Math.min(...data);
    const max = Math.max(...data);
    const range = max - min || 1;

    const pts = data.map((v, i) => ({
      x: padL + (data.length > 1 ? (i / (data.length - 1)) * w : 0),
      y: padTop + h - ((v - min) / range) * h,
    }));

    ctx.clearRect(0, 0, width, height);

    // Gradient fill
    const grad = ctx.createLinearGradient(0, padTop, 0, padTop + h);
    grad.addColorStop(0, glow.replace(/[\d.]+\)$/, '0.3)'));
    grad.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length; i++) {
      const mx = (pts[i - 1].x + pts[i].x) / 2;
      ctx.bezierCurveTo(mx, pts[i - 1].y, mx, pts[i].y, pts[i].x, pts[i].y);
    }
    ctx.lineTo(pts[pts.length - 1].x, padTop + h);
    ctx.lineTo(pts[0].x, padTop + h);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();

    // Line with glow
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length; i++) {
      const mx = (pts[i - 1].x + pts[i].x) / 2;
      ctx.bezierCurveTo(mx, pts[i - 1].y, mx, pts[i].y, pts[i].x, pts[i].y);
    }
    ctx.strokeStyle = color;
    ctx.lineWidth = strokeWidth;
    ctx.shadowColor = glow;
    ctx.shadowBlur = 14;
    ctx.stroke();
    ctx.shadowBlur = 0;

    // Dot on last point
    const last = pts[pts.length - 1];
    ctx.beginPath();
    ctx.arc(last.x, last.y, dotRadius, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.shadowColor = glow;
    ctx.shadowBlur = 20;
    ctx.fill();
    ctx.shadowBlur = 0;
  }, [data, color, glow, width, height, padTop, padBottom, strokeWidth, dotRadius]);

  if (!data.length) return null;
  return <canvas ref={ref} style={{ width, height, display: 'block' }} />;
}
