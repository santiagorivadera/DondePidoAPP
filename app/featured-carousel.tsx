"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";

type Banner = {
  id: string;
  title: string;
  business_id: string;
  business_name: string;
  sector: string;
  image_url: string;
};

export default function FeaturedCarousel() {
  const [banners, setBanners] = useState<Banner[]>([]);
  const [position, setPosition] = useState(0);
  const [failedImages, setFailedImages] = useState<string[]>([]);

  useEffect(() => {
    const controller = new AbortController();
    async function load() {
      try {
        const response = await fetch("/api/featured", { signal: controller.signal });
        if (!response.ok) return;
        const payload: { data?: { banners?: Banner[] } } = await response.json();
        if (!controller.signal.aborted && Array.isArray(payload.data?.banners)) {
          setBanners(payload.data.banners);
        }
      } catch {
        // Featured promotions are optional. The storefront remains available.
      }
    }
    void load();
    return () => controller.abort();
  }, []);

  const banner = banners[position];
  if (!banner) return null;

  function move(step: number) {
    setPosition((previous) => (previous + step + banners.length) % banners.length);
  }

  return (
    <section className="market-section market-featured" aria-labelledby="featured-title">
      <div className="market-section-heading">
        <h2 id="featured-title">Promociones destacadas</h2>
        {banners.length > 1 && (
          <div className="market-featured-controls" role="group" aria-label="Controles de promociones">
            <button className="button secondary" type="button" aria-label="Promoción anterior" onClick={() => move(-1)}>‹</button>
            <button className="button secondary" type="button" aria-label="Promoción siguiente" onClick={() => move(1)}>›</button>
          </div>
        )}
      </div>
      <article className="panel market-featured-card">
        {banner.image_url && !failedImages.includes(banner.id) && (
          <Image
            className="market-featured-image"
            src={banner.image_url}
            width={960}
            height={360}
            alt={banner.title}
            unoptimized
            onError={() => setFailedImages((previous) => [...previous, banner.id])}
          />
        )}
        <div className="market-featured-caption">
          <div>
            <h3>{banner.title}</h3>
            <p className="muted">{banner.business_name}</p>
          </div>
          <Link
            className="button secondary"
            href={{ pathname: "/explorar", query: { rubro: banner.sector, comercio: banner.business_id } }}
            aria-label={`Ver catálogo de ${banner.business_name}`}
          >Ver catálogo</Link>
        </div>
      </article>
      {banners.length > 1 && (
        <p className="market-featured-position muted" aria-live="polite" aria-atomic="true">
          {position + 1} de {banners.length}<span className="market-featured-sr">. {banner.title} de {banner.business_name}</span>
        </p>
      )}
    </section>
  );
}
