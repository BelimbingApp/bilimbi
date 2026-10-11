-- Exact Media DDL excerpt from the pinned Laravel-generated compatibility fixture.

CREATE TABLE public.base_media_assets (
    id bigint NOT NULL,
    parent_id bigint,
    disk character varying(255) NOT NULL,
    storage_key character varying(255) NOT NULL,
    original_filename character varying(255),
    mime_type character varying(255),
    file_size bigint,
    kind character varying(255) NOT NULL,
    metadata json,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone
);

CREATE SEQUENCE public.base_media_assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.base_media_assets_id_seq OWNED BY public.base_media_assets.id;

CREATE TABLE public.base_media_attachments (
    id bigint NOT NULL,
    public_id character(26) NOT NULL,
    tenant_id bigint NOT NULL,
    media_asset_id bigint NOT NULL,
    subject_type character varying(255) NOT NULL,
    subject_id character varying(255) NOT NULL,
    state character varying(255) NOT NULL,
    uploaded_by_type character varying(255) NOT NULL,
    uploaded_by_id bigint NOT NULL,
    submitted_at timestamp(0) without time zone,
    created_at timestamp(0) without time zone,
    updated_at timestamp(0) without time zone,
    retained_at timestamp(0) without time zone
);

CREATE SEQUENCE public.base_media_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.base_media_attachments_id_seq OWNED BY public.base_media_attachments.id;

ALTER TABLE ONLY public.base_media_assets ALTER COLUMN id SET DEFAULT nextval('public.base_media_assets_id_seq'::regclass);

ALTER TABLE ONLY public.base_media_attachments ALTER COLUMN id SET DEFAULT nextval('public.base_media_attachments_id_seq'::regclass);

ALTER TABLE ONLY public.base_media_assets
    ADD CONSTRAINT base_media_assets_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.base_media_attachments
    ADD CONSTRAINT base_media_attachments_media_asset_id_unique UNIQUE (media_asset_id);

ALTER TABLE ONLY public.base_media_attachments
    ADD CONSTRAINT base_media_attachments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.base_media_attachments
    ADD CONSTRAINT base_media_attachments_public_id_unique UNIQUE (public_id);

CREATE INDEX base_media_assets_disk_storage_key_index ON public.base_media_assets USING btree (disk, storage_key);

CREATE INDEX base_media_assets_kind_index ON public.base_media_assets USING btree (kind);

CREATE INDEX base_media_assets_parent_id_kind_index ON public.base_media_assets USING btree (parent_id, kind);

CREATE INDEX base_media_attachments_retained_at_index ON public.base_media_attachments USING btree (retained_at);

CREATE INDEX base_media_attachments_state_index ON public.base_media_attachments USING btree (state);

CREATE INDEX media_attachments_draft_cleanup_idx ON public.base_media_attachments USING btree (tenant_id, state, created_at);

CREATE INDEX media_attachments_tenant_subject_idx ON public.base_media_attachments USING btree (tenant_id, subject_type, subject_id);

ALTER TABLE ONLY public.base_media_assets
    ADD CONSTRAINT base_media_assets_parent_id_foreign FOREIGN KEY (parent_id) REFERENCES public.base_media_assets(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.base_media_attachments
    ADD CONSTRAINT base_media_attachments_media_asset_id_foreign FOREIGN KEY (media_asset_id) REFERENCES public.base_media_assets(id) ON DELETE RESTRICT;

ALTER TABLE ONLY public.base_media_attachments
    ADD CONSTRAINT base_media_attachments_tenant_id_foreign FOREIGN KEY (tenant_id) REFERENCES public.tenants(id) ON DELETE CASCADE;
