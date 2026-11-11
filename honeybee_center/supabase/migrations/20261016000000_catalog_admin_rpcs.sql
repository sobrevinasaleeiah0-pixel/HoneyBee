BEGIN;

CREATE OR REPLACE FUNCTION public.create_catalog_product(
  p_name text,
  p_variety text,
  p_category text,
  p_description text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  v_product_id uuid;
BEGIN
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'create_catalog_product: co_admin role required';
  END IF;

  IF NULLIF(btrim(p_name), '') IS NULL THEN
    RAISE EXCEPTION 'Product name is required';
  END IF;

  INSERT INTO public.products (
    external_id, name, variety, category, description, is_active
  ) 
  VALUES (
    'prod_' || gen_random_uuid()::text,
    btrim(p_name),
    NULLIF(btrim(p_variety), ''),
    NULLIF(btrim(p_category), ''),
    NULLIF(btrim(p_description), ''),
    true
  )
  RETURNING id INTO v_product_id;

  RETURN v_product_id;
END;
$function$;

ALTER FUNCTION public.create_catalog_product(text, text, text, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_catalog_product(text, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_catalog_product(text, text, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.update_catalog_product(
  p_product_id uuid,
  p_name text,
  p_variety text,
  p_category text,
  p_description text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'update_catalog_product: co_admin role required';
  END IF;

  IF NULLIF(btrim(p_name), '') IS NULL THEN
    RAISE EXCEPTION 'Product name is required';
  END IF;

  UPDATE public.products
     SET name = btrim(p_name),
         variety = NULLIF(btrim(p_variety), ''),
         category = NULLIF(btrim(p_category), ''),
         description = NULLIF(btrim(p_description), ''),
         updated_at = now()
   WHERE id = p_product_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product % not found', p_product_id;
  END IF;
END;
$function$;

ALTER FUNCTION public.update_catalog_product(uuid, text, text, text, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.update_catalog_product(uuid, text, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_catalog_product(uuid, text, text, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.update_catalog_product(
  p_product_id uuid,
  p_name text,
  p_variety text,
  p_description text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'update_catalog_product: co_admin role required';
  END IF;

  PERFORM public.update_catalog_product(
    p_product_id,
    p_name,
    p_variety,
    (SELECT p.category FROM public.products AS p WHERE p.id = p_product_id),
    p_description
  );
END;
$function$;

ALTER FUNCTION public.update_catalog_product(uuid, text, text, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.update_catalog_product(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_catalog_product(uuid, text, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.set_catalog_product_active(
  p_product_id uuid,
  p_is_active boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'set_catalog_product_active: co_admin role required';
  END IF;

  UPDATE public.products
     SET is_active = p_is_active,
         updated_at = now()
   WHERE id = p_product_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product % not found', p_product_id;
  END IF;
END;
$function$;

ALTER FUNCTION public.set_catalog_product_active(uuid, boolean)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.set_catalog_product_active(uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_catalog_product_active(uuid, boolean)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.create_catalog_variant(
  p_product_id uuid,
  p_size text,
  p_price integer,
  p_reorder_level integer
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  v_variant_id uuid;
BEGIN
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'create_catalog_variant: co_admin role required';
  END IF;

  IF NULLIF(btrim(p_size), '') IS NULL THEN
    RAISE EXCEPTION 'Variant size is required';
  END IF;
  IF p_price IS NULL OR p_price <= 0 THEN
    RAISE EXCEPTION 'Variant price must be greater than zero';
  END IF;
  IF p_reorder_level IS NULL OR p_reorder_level < 0 THEN
    RAISE EXCEPTION 'Reorder level cannot be negative';
  END IF;
  PERFORM 1 FROM public.products WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product % not found', p_product_id;
  END IF;

  INSERT INTO public.product_variants (
    external_id, product_id, size, price, reorder_level, product_qty, is_active
  )
  VALUES (
    'variant_' || gen_random_uuid()::text,
    p_product_id,
    btrim(p_size),
    p_price,
    p_reorder_level,
    0,
    true
  )
  RETURNING id INTO v_variant_id;

  INSERT INTO public.inventory (product_id, variant_id, quantity)
  VALUES (p_product_id, v_variant_id, 0);

  RETURN v_variant_id;
END;
$function$;

ALTER FUNCTION public.create_catalog_variant(uuid, text, integer, integer)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_catalog_variant(uuid, text, integer, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_catalog_variant(uuid, text, integer, integer)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.update_catalog_variant(
  p_variant_id uuid,
  p_price integer,
  p_reorder_level integer,
  p_is_active boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'update_catalog_variant: co_admin role required';
  END IF;

  IF p_price IS NULL OR p_price <= 0 THEN
    RAISE EXCEPTION 'Variant price must be greater than zero';
  END IF;
  IF p_reorder_level IS NULL OR p_reorder_level < 0 THEN
    RAISE EXCEPTION 'Reorder level cannot be negative';
  END IF;

  UPDATE public.product_variants
     SET price = p_price,
         reorder_level = p_reorder_level,
         is_active = p_is_active,
         updated_at = now()
   WHERE id = p_variant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Variant % not found', p_variant_id;
  END IF;
END;
$function$;

ALTER FUNCTION public.update_catalog_variant(uuid, integer, integer, boolean)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.update_catalog_variant(uuid, integer, integer, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_catalog_variant(uuid, integer, integer, boolean)
  TO authenticated;

COMMIT;
