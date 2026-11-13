import Account from "./account";

export default async function AccountPage({ searchParams }: {
  searchParams: Promise<{ vista?: string | string[]; next?: string | string[] }>;
}) {
  const { vista, next } = await searchParams;
  const destination = typeof next === "string" && ["/", "/explorar", "/carrito", "/pedidos"].includes(next)
    ? next : undefined;
  return <Account view={typeof vista === "string" ? vista : undefined} destination={destination} />;
}
