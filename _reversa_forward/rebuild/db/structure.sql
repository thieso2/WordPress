SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: comment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.comment_status AS ENUM (
    'pending',
    'approved',
    'spam',
    'trashed'
);


--
-- Name: post_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.post_status AS ENUM (
    'auto_draft',
    'draft',
    'pending',
    'scheduled',
    'published',
    'private',
    'trashed'
);


--
-- Name: classification_assignment_counts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.classification_assignment_counts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM classification_refresh_term_counts(ARRAY[OLD.term_id]);
    RETURN OLD;
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM classification_refresh_term_counts(ARRAY[OLD.term_id, NEW.term_id]);
    RETURN NEW;
  ELSE
    PERFORM classification_refresh_term_counts(ARRAY[NEW.term_id]);
    RETURN NEW;
  END IF;
END;
$$;


--
-- Name: classification_post_counts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.classification_post_counts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE affected bigint[];
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- The polymorphic cascade no FK can carry. Removing the rows fires the
    -- assignment trigger above, which is what decrements the counts.
    DELETE FROM term_assignments
     WHERE classifiable_type = 'Publishing::Post' AND classifiable_id = OLD.id;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  SELECT array_agg(term_id) INTO affected FROM term_assignments
   WHERE classifiable_type = 'Publishing::Post' AND classifiable_id = NEW.id;
  PERFORM classification_refresh_term_counts(affected);
  RETURN NEW;
END;
$$;


--
-- Name: classification_refresh_term_counts(bigint[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.classification_refresh_term_counts(p_term_ids bigint[]) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  seed  bigint;
  node  bigint;
  steps integer;
BEGIN
  FOREACH seed IN ARRAY coalesce(p_term_ids, ARRAY[]::bigint[]) LOOP
    node  := seed;
    steps := 0;
    WHILE node IS NOT NULL AND steps < 1000 LOOP
      UPDATE terms SET count = classification_term_count(node) WHERE id = node;
      SELECT parent_id INTO node FROM terms WHERE id = node;
      steps := steps + 1;
    END LOOP;
  END LOOP;
END;
$$;


--
-- Name: classification_term_count(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.classification_term_count(p_term_id bigint) RETURNS integer
    LANGUAGE sql STABLE
    AS $$
  WITH RECURSIVE subtree(id) AS (
    SELECT p_term_id
    UNION ALL
    SELECT t.id FROM terms t JOIN subtree s ON t.parent_id = s.id
  )
  SELECT count(DISTINCT a.classifiable_id)::integer
  FROM term_assignments a
  JOIN subtree s ON s.id = a.term_id
  JOIN posts p ON p.id = a.classifiable_id
  WHERE a.classifiable_type = 'Publishing::Post'
    AND p.status = 'published';
$$;


--
-- Name: classification_term_reparent_counts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.classification_term_reparent_counts() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM classification_refresh_term_counts(ARRAY[NEW.id]);
  IF OLD.parent_id IS NOT NULL THEN
    PERFORM classification_refresh_term_counts(ARRAY[OLD.parent_id]);
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: detach_assets_from_deleted_post(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.detach_assets_from_deleted_post() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE assets SET attached_to_id = NULL WHERE attached_to_id = OLD.id;
  RETURN OLD;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: application_passwords; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.application_passwords (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    name text NOT NULL,
    digest text NOT NULL,
    last_used_at timestamp with time zone,
    last_ip inet,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: application_passwords_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.application_passwords ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.application_passwords_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: asset_variants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset_variants (
    id bigint NOT NULL,
    asset_id bigint NOT NULL,
    size_name text NOT NULL,
    width integer NOT NULL,
    height integer NOT NULL,
    mime_type text NOT NULL
);


--
-- Name: asset_variants_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.asset_variants ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.asset_variants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assets (
    id bigint NOT NULL,
    uploader_id bigint,
    attached_to_id bigint,
    title text DEFAULT ''::text NOT NULL,
    slug text NOT NULL,
    alt_text text DEFAULT ''::text NOT NULL,
    caption text DEFAULT ''::text NOT NULL,
    mime_type text NOT NULL,
    byte_size bigint NOT NULL,
    width integer,
    height integer,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: COLUMN assets.attached_to_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.assets.attached_to_id IS 'Legacy post_parent: the post being edited at upload time. Provenance, not structure. Deliberately NOT a foreign key — see db/migrate/20260822000060 and the owner ruling that broke the Publishing <-> Library cycle.';


--
-- Name: assets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.assets ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: comment_rate_limits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comment_rate_limits (
    id bigint NOT NULL,
    author_key text NOT NULL,
    window_start timestamp with time zone NOT NULL,
    count integer DEFAULT 0 NOT NULL
);


--
-- Name: comment_rate_limits_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.comment_rate_limits ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.comment_rate_limits_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comments (
    id bigint NOT NULL,
    post_id bigint NOT NULL,
    parent_id bigint,
    user_id bigint,
    author_name text DEFAULT ''::text NOT NULL,
    author_email public.citext,
    author_url text,
    author_ip inet,
    user_agent text,
    content text NOT NULL,
    status public.comment_status DEFAULT 'pending'::public.comment_status NOT NULL,
    kind text DEFAULT 'comment'::text NOT NULL,
    submitted_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: comments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.comments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.comments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: data_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.data_requests (
    id bigint NOT NULL,
    user_id bigint,
    email public.citext NOT NULL,
    kind text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    confirmed_at timestamp with time zone,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    confirm_key_digest text,
    confirm_key_sent_at timestamp with time zone,
    CONSTRAINT data_requests_kind_check CHECK ((kind = ANY (ARRAY['export'::text, 'erasure'::text])))
);


--
-- Name: data_requests_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.data_requests ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.data_requests_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: embed_caches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.embed_caches (
    id bigint NOT NULL,
    url_digest text NOT NULL,
    payload jsonb NOT NULL,
    fetched_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: embed_caches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.embed_caches ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.embed_caches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: menu_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menu_items (
    id bigint NOT NULL,
    menu_id bigint NOT NULL,
    parent_id bigint,
    "position" integer DEFAULT 0 NOT NULL,
    target_type text,
    target_id bigint,
    url text,
    label text DEFAULT ''::text NOT NULL,
    title text DEFAULT ''::text NOT NULL,
    css_classes text[] DEFAULT '{}'::text[] NOT NULL,
    xfn text DEFAULT ''::text NOT NULL,
    CONSTRAINT menu_items_one_target CHECK ((((target_type IS NOT NULL) AND (target_id IS NOT NULL) AND (url IS NULL)) OR ((target_type IS NULL) AND (target_id IS NULL) AND (url IS NOT NULL))))
);


--
-- Name: menu_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.menu_items ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.menu_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: menus; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menus (
    id bigint NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    location text
);


--
-- Name: menus_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.menus ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.menus_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: moderation_verdicts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.moderation_verdicts (
    id bigint NOT NULL,
    comment_id bigint NOT NULL,
    outcome text NOT NULL,
    reason text NOT NULL,
    decided_by bigint,
    decided_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: moderation_verdicts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.moderation_verdicts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.moderation_verdicts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: network_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.network_settings (
    id bigint NOT NULL,
    name character varying NOT NULL,
    value jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: network_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.network_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: network_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.network_settings_id_seq OWNED BY public.network_settings.id;


--
-- Name: patterns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.patterns (
    id bigint NOT NULL,
    slug text NOT NULL,
    title text NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    categories text[] DEFAULT '{}'::text[] NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    inserter boolean DEFAULT true NOT NULL
);


--
-- Name: patterns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.patterns ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.patterns_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: post_attributes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_attributes (
    id bigint NOT NULL,
    post_id bigint NOT NULL,
    key text NOT NULL,
    value jsonb NOT NULL
);


--
-- Name: post_attributes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.post_attributes ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.post_attributes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: post_status_transitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.post_status_transitions (
    id bigint NOT NULL,
    post_id bigint NOT NULL,
    from_status public.post_status,
    to_status public.post_status NOT NULL,
    actor_id bigint,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: post_status_transitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.post_status_transitions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.post_status_transitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    id bigint NOT NULL,
    type text DEFAULT 'Publishing::Article'::text NOT NULL,
    author_id bigint,
    parent_id bigint,
    featured_asset_id bigint,
    title text DEFAULT ''::text NOT NULL,
    slug text,
    content text DEFAULT ''::text NOT NULL,
    excerpt text DEFAULT ''::text NOT NULL,
    status public.post_status DEFAULT 'draft'::public.post_status NOT NULL,
    published_at timestamp with time zone,
    modified_at timestamp with time zone DEFAULT now() NOT NULL,
    trashed_at timestamp with time zone,
    status_before_trash public.post_status,
    comment_status text DEFAULT 'open'::text NOT NULL,
    password_digest text,
    menu_order integer DEFAULT 0 NOT NULL,
    guid uuid DEFAULT gen_random_uuid() NOT NULL,
    template_slug text,
    comment_count integer DEFAULT 0 NOT NULL,
    residual_attributes jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    edit_lock_at timestamp with time zone,
    edit_lock_by_id bigint,
    CONSTRAINT posts_published_at_present CHECK (((status <> ALL (ARRAY['published'::public.post_status, 'scheduled'::public.post_status])) OR (published_at IS NOT NULL))),
    CONSTRAINT posts_slug_length CHECK (((slug IS NULL) OR (octet_length(slug) <= 200))),
    CONSTRAINT posts_trash_consistent CHECK ((((trashed_at IS NULL) AND (status_before_trash IS NULL)) OR ((trashed_at IS NOT NULL) AND (status_before_trash IS NOT NULL))))
);


--
-- Name: posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.posts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: redirects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.redirects (
    id bigint NOT NULL,
    from_path text NOT NULL,
    post_id bigint,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: redirects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.redirects ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.redirects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.revisions (
    id bigint NOT NULL,
    post_id bigint NOT NULL,
    author_id bigint,
    title text DEFAULT ''::text NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    excerpt text DEFAULT ''::text NOT NULL,
    autosave boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.revisions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: role_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_assignments (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    role text NOT NULL,
    site_id bigint,
    granted_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: role_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.role_assignments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.role_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    token_digest text NOT NULL,
    ip inet,
    user_agent text,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sessions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings (
    id bigint NOT NULL,
    name text NOT NULL,
    value jsonb NOT NULL,
    autoload boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.settings ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: signups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.signups (
    id bigint NOT NULL,
    kind character varying DEFAULT 'blog'::character varying NOT NULL,
    user_login character varying NOT NULL,
    user_email character varying NOT NULL,
    domain character varying,
    path character varying,
    title character varying,
    activation_key character varying NOT NULL,
    activated_at timestamp(6) without time zone,
    site_id bigint,
    meta jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: signups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.signups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: signups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.signups_id_seq OWNED BY public.signups.id;


--
-- Name: sites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sites (
    id bigint NOT NULL,
    schema_name character varying NOT NULL,
    domain character varying NOT NULL,
    path character varying DEFAULT '/'::character varying NOT NULL,
    name character varying DEFAULT ''::character varying NOT NULL,
    public boolean DEFAULT true NOT NULL,
    archived boolean DEFAULT false NOT NULL,
    deleted boolean DEFAULT false NOT NULL,
    spam boolean DEFAULT false NOT NULL,
    registered_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: sites_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sites_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sites_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sites_id_seq OWNED BY public.sites.id;


--
-- Name: taxonomies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taxonomies (
    id bigint NOT NULL,
    name text NOT NULL,
    hierarchical boolean DEFAULT false NOT NULL,
    object_types text[] DEFAULT '{}'::text[] NOT NULL
);


--
-- Name: taxonomies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.taxonomies ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.taxonomies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.templates (
    id bigint NOT NULL,
    theme_slug text NOT NULL,
    slug text NOT NULL,
    area text,
    kind text NOT NULL,
    content text DEFAULT ''::text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    title text DEFAULT ''::text NOT NULL,
    CONSTRAINT templates_kind_check CHECK ((kind = ANY (ARRAY['template'::text, 'part'::text, 'navigation'::text])))
);


--
-- Name: templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.templates ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: term_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.term_assignments (
    id bigint NOT NULL,
    term_id bigint NOT NULL,
    classifiable_type text NOT NULL,
    classifiable_id bigint NOT NULL,
    "position" integer DEFAULT 0 NOT NULL
);


--
-- Name: term_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.term_assignments ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.term_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: terms; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.terms (
    id bigint NOT NULL,
    taxonomy_id bigint NOT NULL,
    parent_id bigint,
    name text NOT NULL,
    slug text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT terms_not_self_parent CHECK ((parent_id IS DISTINCT FROM id))
);


--
-- Name: terms_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.terms ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.terms_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: themes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.themes (
    id bigint NOT NULL,
    slug text NOT NULL,
    parent_slug text,
    version text NOT NULL,
    active boolean DEFAULT false NOT NULL,
    theme_json json DEFAULT '{}'::json NOT NULL,
    user_styles json
);


--
-- Name: themes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.themes ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.themes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    login public.citext NOT NULL,
    email public.citext NOT NULL,
    password_digest text NOT NULL,
    nicename public.citext NOT NULL,
    display_name text DEFAULT ''::text NOT NULL,
    url text,
    status text DEFAULT 'active'::text NOT NULL,
    registered_at timestamp with time zone DEFAULT now() NOT NULL,
    activation_key_digest text,
    locale text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.users ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: network_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.network_settings ALTER COLUMN id SET DEFAULT nextval('public.network_settings_id_seq'::regclass);


--
-- Name: signups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signups ALTER COLUMN id SET DEFAULT nextval('public.signups_id_seq'::regclass);


--
-- Name: sites id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sites ALTER COLUMN id SET DEFAULT nextval('public.sites_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: application_passwords application_passwords_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_passwords
    ADD CONSTRAINT application_passwords_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: asset_variants asset_variants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_variants
    ADD CONSTRAINT asset_variants_pkey PRIMARY KEY (id);


--
-- Name: assets assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_pkey PRIMARY KEY (id);


--
-- Name: comment_rate_limits comment_rate_limits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comment_rate_limits
    ADD CONSTRAINT comment_rate_limits_pkey PRIMARY KEY (id);


--
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);


--
-- Name: data_requests data_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_requests
    ADD CONSTRAINT data_requests_pkey PRIMARY KEY (id);


--
-- Name: embed_caches embed_caches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.embed_caches
    ADD CONSTRAINT embed_caches_pkey PRIMARY KEY (id);


--
-- Name: menu_items menu_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_pkey PRIMARY KEY (id);


--
-- Name: menus menus_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menus
    ADD CONSTRAINT menus_pkey PRIMARY KEY (id);


--
-- Name: moderation_verdicts moderation_verdicts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_verdicts
    ADD CONSTRAINT moderation_verdicts_pkey PRIMARY KEY (id);


--
-- Name: network_settings network_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.network_settings
    ADD CONSTRAINT network_settings_pkey PRIMARY KEY (id);


--
-- Name: patterns patterns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patterns
    ADD CONSTRAINT patterns_pkey PRIMARY KEY (id);


--
-- Name: post_attributes post_attributes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_attributes
    ADD CONSTRAINT post_attributes_pkey PRIMARY KEY (id);


--
-- Name: post_status_transitions post_status_transitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_status_transitions
    ADD CONSTRAINT post_status_transitions_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: redirects redirects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redirects
    ADD CONSTRAINT redirects_pkey PRIMARY KEY (id);


--
-- Name: revisions revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revisions
    ADD CONSTRAINT revisions_pkey PRIMARY KEY (id);


--
-- Name: role_assignments role_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT role_assignments_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (id);


--
-- Name: signups signups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signups
    ADD CONSTRAINT signups_pkey PRIMARY KEY (id);


--
-- Name: sites sites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sites
    ADD CONSTRAINT sites_pkey PRIMARY KEY (id);


--
-- Name: taxonomies taxonomies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taxonomies
    ADD CONSTRAINT taxonomies_pkey PRIMARY KEY (id);


--
-- Name: templates templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.templates
    ADD CONSTRAINT templates_pkey PRIMARY KEY (id);


--
-- Name: term_assignments term_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term_assignments
    ADD CONSTRAINT term_assignments_pkey PRIMARY KEY (id);


--
-- Name: terms terms_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.terms
    ADD CONSTRAINT terms_pkey PRIMARY KEY (id);


--
-- Name: themes themes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.themes
    ADD CONSTRAINT themes_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: asset_variants_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX asset_variants_unique ON public.asset_variants USING btree (asset_id, size_name);


--
-- Name: assets_attached_to; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX assets_attached_to ON public.assets USING btree (attached_to_id);


--
-- Name: assets_slug_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX assets_slug_key ON public.assets USING btree (slug);


--
-- Name: comment_rate_limits_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX comment_rate_limits_key ON public.comment_rate_limits USING btree (author_key, window_start);


--
-- Name: comments_author_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comments_author_email ON public.comments USING btree (author_email);


--
-- Name: comments_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comments_parent ON public.comments USING btree (parent_id);


--
-- Name: comments_post_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX comments_post_status ON public.comments USING btree (post_id, status, submitted_at DESC);


--
-- Name: embed_caches_expiry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX embed_caches_expiry ON public.embed_caches USING btree (expires_at);


--
-- Name: embed_caches_url_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX embed_caches_url_key ON public.embed_caches USING btree (url_digest);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_network_settings_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_network_settings_on_name ON public.network_settings USING btree (name);


--
-- Name: index_signups_on_activation_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_signups_on_activation_key ON public.signups USING btree (activation_key);


--
-- Name: index_signups_on_site_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_signups_on_site_id ON public.signups USING btree (site_id);


--
-- Name: index_signups_on_user_login; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_signups_on_user_login ON public.signups USING btree (user_login);


--
-- Name: index_sites_on_domain_and_path; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sites_on_domain_and_path ON public.sites USING btree (domain, path);


--
-- Name: index_sites_on_schema_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sites_on_schema_name ON public.sites USING btree (schema_name);


--
-- Name: index_templates_on_theme_kind_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_templates_on_theme_kind_slug ON public.templates USING btree (theme_slug, kind, slug);


--
-- Name: menu_items_menu; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX menu_items_menu ON public.menu_items USING btree (menu_id, "position");


--
-- Name: menus_slug_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX menus_slug_key ON public.menus USING btree (slug);


--
-- Name: patterns_slug_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX patterns_slug_key ON public.patterns USING btree (slug);


--
-- Name: post_attributes_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX post_attributes_unique ON public.post_attributes USING btree (post_id, key);


--
-- Name: post_status_transitions_post; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX post_status_transitions_post ON public.post_status_transitions USING btree (post_id, occurred_at DESC);


--
-- Name: posts_edit_lock_by; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_edit_lock_by ON public.posts USING btree (edit_lock_by_id) WHERE (edit_lock_by_id IS NOT NULL);


--
-- Name: posts_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_parent ON public.posts USING btree (parent_id);


--
-- Name: posts_residual_attributes_gin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_residual_attributes_gin ON public.posts USING gin (residual_attributes jsonb_path_ops);


--
-- Name: posts_slug_hierarchical; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX posts_slug_hierarchical ON public.posts USING btree (type, COALESCE(parent_id, (0)::bigint), slug) WHERE (slug IS NOT NULL);


--
-- Name: posts_type_status_author; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_type_status_author ON public.posts USING btree (type, status, author_id);


--
-- Name: posts_type_status_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX posts_type_status_published ON public.posts USING btree (type, status, published_at DESC NULLS LAST, id);


--
-- Name: redirects_from_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX redirects_from_key ON public.redirects USING btree (from_path);


--
-- Name: revisions_post; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX revisions_post ON public.revisions USING btree (post_id, created_at DESC);


--
-- Name: role_assignments_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX role_assignments_unique ON public.role_assignments USING btree (user_id, role, COALESCE(site_id, (0)::bigint));


--
-- Name: sessions_token_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX sessions_token_key ON public.sessions USING btree (token_digest);


--
-- Name: sessions_user_expiry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sessions_user_expiry ON public.sessions USING btree (user_id, expires_at);


--
-- Name: settings_autoload; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX settings_autoload ON public.settings USING btree (autoload) WHERE autoload;


--
-- Name: settings_name_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX settings_name_key ON public.settings USING btree (name);


--
-- Name: taxonomies_name_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX taxonomies_name_key ON public.taxonomies USING btree (name);


--
-- Name: templates_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX templates_unique ON public.templates USING btree (theme_slug, kind, slug);


--
-- Name: term_assignments_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX term_assignments_target ON public.term_assignments USING btree (classifiable_type, classifiable_id);


--
-- Name: term_assignments_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX term_assignments_unique ON public.term_assignments USING btree (term_id, classifiable_type, classifiable_id);


--
-- Name: terms_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX terms_parent ON public.terms USING btree (parent_id);


--
-- Name: terms_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX terms_unique ON public.terms USING btree (taxonomy_id, COALESCE(parent_id, (0)::bigint), slug);


--
-- Name: themes_slug_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX themes_slug_key ON public.themes USING btree (slug);


--
-- Name: users_email_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_email_key ON public.users USING btree (email);


--
-- Name: users_login_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_login_key ON public.users USING btree (login);


--
-- Name: users_nicename_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_nicename_key ON public.users USING btree (nicename);


--
-- Name: posts posts_detach_assets; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER posts_detach_assets BEFORE DELETE ON public.posts FOR EACH ROW EXECUTE FUNCTION public.detach_assets_from_deleted_post();


--
-- Name: posts posts_maintain_term_counts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER posts_maintain_term_counts AFTER INSERT OR DELETE OR UPDATE ON public.posts FOR EACH ROW EXECUTE FUNCTION public.classification_post_counts();


--
-- Name: term_assignments term_assignments_maintain_counts; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER term_assignments_maintain_counts AFTER INSERT OR DELETE OR UPDATE ON public.term_assignments FOR EACH ROW EXECUTE FUNCTION public.classification_assignment_counts();


--
-- Name: terms terms_maintain_counts_on_reparent; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER terms_maintain_counts_on_reparent AFTER UPDATE OF parent_id ON public.terms FOR EACH ROW WHEN ((old.parent_id IS DISTINCT FROM new.parent_id)) EXECUTE FUNCTION public.classification_term_reparent_counts();


--
-- Name: application_passwords application_passwords_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.application_passwords
    ADD CONSTRAINT application_passwords_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: asset_variants asset_variants_asset_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_variants
    ADD CONSTRAINT asset_variants_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES public.assets(id) ON DELETE CASCADE;


--
-- Name: assets assets_uploader_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_uploader_id_fkey FOREIGN KEY (uploader_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: comments comments_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- Name: comments comments_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: comments comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: data_requests data_requests_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.data_requests
    ADD CONSTRAINT data_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: signups fk_rails_b9037c998d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signups
    ADD CONSTRAINT fk_rails_b9037c998d FOREIGN KEY (site_id) REFERENCES public.sites(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: menu_items menu_items_menu_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_menu_id_fkey FOREIGN KEY (menu_id) REFERENCES public.menus(id) ON DELETE CASCADE;


--
-- Name: menu_items menu_items_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.menu_items(id) ON DELETE CASCADE;


--
-- Name: moderation_verdicts moderation_verdicts_comment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_verdicts
    ADD CONSTRAINT moderation_verdicts_comment_id_fkey FOREIGN KEY (comment_id) REFERENCES public.comments(id) ON DELETE CASCADE;


--
-- Name: moderation_verdicts moderation_verdicts_decided_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_verdicts
    ADD CONSTRAINT moderation_verdicts_decided_by_fkey FOREIGN KEY (decided_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: post_attributes post_attributes_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_attributes
    ADD CONSTRAINT post_attributes_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: post_status_transitions post_status_transitions_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_status_transitions
    ADD CONSTRAINT post_status_transitions_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: post_status_transitions post_status_transitions_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.post_status_transitions
    ADD CONSTRAINT post_status_transitions_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: posts posts_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: posts posts_edit_lock_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_edit_lock_by_id_fkey FOREIGN KEY (edit_lock_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: posts posts_featured_asset_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_featured_asset_fk FOREIGN KEY (featured_asset_id) REFERENCES public.assets(id) ON DELETE SET NULL;


--
-- Name: posts posts_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: redirects redirects_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redirects
    ADD CONSTRAINT redirects_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: revisions revisions_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revisions
    ADD CONSTRAINT revisions_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: revisions revisions_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.revisions
    ADD CONSTRAINT revisions_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: role_assignments role_assignments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_assignments
    ADD CONSTRAINT role_assignments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: term_assignments term_assignments_term_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.term_assignments
    ADD CONSTRAINT term_assignments_term_id_fkey FOREIGN KEY (term_id) REFERENCES public.terms(id) ON DELETE CASCADE;


--
-- Name: terms terms_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.terms
    ADD CONSTRAINT terms_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.terms(id) ON DELETE CASCADE;


--
-- Name: terms terms_taxonomy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.terms
    ADD CONSTRAINT terms_taxonomy_id_fkey FOREIGN KEY (taxonomy_id) REFERENCES public.taxonomies(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260823000400'),
('20260823000300'),
('20260823000010'),
('20260822000110'),
('20260822000100'),
('20260822000090'),
('20260822000080'),
('20260822000070'),
('20260822000061'),
('20260822000060'),
('20260822000052'),
('20260822000011'),
('20260822000010'),
('20260822000009'),
('20260822000008'),
('20260822000007'),
('20260822000006'),
('20260822000005'),
('20260822000004'),
('20260822000003'),
('20260822000002'),
('20260822000001');

