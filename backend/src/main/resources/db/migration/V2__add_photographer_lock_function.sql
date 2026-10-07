SET search_path TO scheduling, public;

CREATE OR REPLACE FUNCTION scheduling.lock_request_photographer()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scheduling, pg_temp
AS $$
DECLARE
    v_photographer_id uuid;
BEGIN
    v_photographer_id :=
        nullif(current_setting('app.photographer_id', true), '')::uuid;

    IF v_photographer_id IS NULL THEN
        RAISE EXCEPTION 'photographer context is required'
            USING ERRCODE = '42501';
    END IF;

    PERFORM 1
    FROM scheduling.photographers
    WHERE id = v_photographer_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'photographer not found for current context'
            USING ERRCODE = '42501';
    END IF;

    RETURN v_photographer_id;
END;
$$;

REVOKE ALL
ON FUNCTION scheduling.lock_request_photographer()
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION scheduling.lock_request_photographer()
TO jm_tenant;
