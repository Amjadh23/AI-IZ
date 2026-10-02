-- =====================================================================
-- AI-IZ live quiz · Supabase setup
--
-- 1. Supabase → SQL Editor → New query → paste this whole file as it is
--    → Run. Safe to run again later: it refreshes questions and
--    functions and keeps players, scores and your PIN.
-- 2. Then set your presenter PIN in a new query (6+ characters, e.g. a
--    word plus numbers) and run it:
--
--      update quiz_secret set pin = 'your-pin-here';
--
--    You type the same PIN into the deck once, on the Quizzies slide.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------
create table if not exists quiz_secret (
  id  int primary key default 1 check (id = 1),
  pin text not null
);

create table if not exists quiz_state (
  id         int primary key default 1 check (id = 1),
  session    text not null default 'setup',
  q          int  not null default 0,              -- 0 = lobby, 1–10 = question
  phase      text not null default 'lobby'
             check (phase in ('lobby', 'open', 'closed', 'revealed', 'done')),
  opened_at  timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists quiz_questions (
  q       int primary key,
  prompt  text  not null,
  options jsonb not null,
  seconds int   not null default 20
);

-- The answer key. Phones can never read this table.
create table if not exists quiz_key (
  q       int primary key references quiz_questions (q) on delete cascade,
  answer  int not null check (answer between 0 and 3),
  explain text
);

create table if not exists quiz_players (
  id         uuid primary key default gen_random_uuid(),
  session    text not null,
  name       text not null,
  hidden     boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists quiz_players_session on quiz_players (session);

create table if not exists quiz_answers (
  player_id  uuid not null references quiz_players (id) on delete cascade,
  q          int  not null,
  choice     int  not null,
  correct    boolean not null,
  points     int  not null,
  ms         int  not null,
  created_at timestamptz not null default now(),
  primary key (player_id, q)
);

-- ---------------------------------------------------------------------
-- Seed: presenter PIN, game state, questions (generated from the deck)
-- ---------------------------------------------------------------------
insert into quiz_secret (id, pin) values (1, 'CHANGE-ME')
on conflict (id) do nothing;

insert into quiz_state (id) values (1) on conflict (id) do nothing;

insert into quiz_questions (q, prompt, options, seconds) values
  (1, 'In Google''s 4-part prompt formula, which part is the only must-have?', '["Persona", "Task", "Context", "Format"]'::jsonb, 20),
  (2, 'Adding "Let''s think step by step" raised the model''s MultiArith maths score from 17.7% to…', '["25.4%", "48.1%", "78.7%", "99.9%"]'::jsonb, 20),
  (3, 'What''s the best way to stop the AI mixing up your instructions with the notes you pasted?', '["Write everything in ALL CAPS", "Say please twice", "Add more emojis", "Wrap the notes in tags like <notes>…</notes>"]'::jsonb, 20),
  (4, 'The AI gives you a statistic with a neat-looking source. What should you do?', '["Verify it: AI can invent sources", "Paste it straight into your assignment", "Ask it to make the number bigger", "Trust it if it sounds confident"]'::jsonb, 20),
  (5, 'What does MCP stand for?', '["Machine Control Program", "Multi-Chat Platform", "Model Context Protocol", "Model Compute Processor"]'::jsonb, 20),
  (6, 'MCP''s official docs describe it as a ___ for AI applications.', '["Wi-Fi router", "Bluetooth speaker", "HDMI cable", "USB-C port"]'::jsonb, 20),
  (7, 'Which statement about Skills and MCP is correct?', '["MCP gives AI access to tools; Skills teach it how to do a job", "Skills connect AI to apps; MCP is a recipe file", "They are exactly the same thing", "Both only work offline"]'::jsonb, 20),
  (8, 'Roughly how many characters of English make up one token?', '["1", "4", "10", "50"]'::jsonb, 20),
  (9, 'Why do very long chats use up your limit faster?', '["The AI gets tired", "Long chats switch to a pricier model", "The whole chat is re-sent with every new message", "They don''t. Length doesn''t matter"]'::jsonb, 20),
  (10, 'On Claude''s API, output tokens cost ___ input tokens.', '["the same as", "half the price of", "2× the price of", "5× the price of"]'::jsonb, 20),
  (11, 'How many tokens is "supercalifragilisticexpialidocious" in OpenAI''s tokenizer?', '["1", "5", "10", "34"]'::jsonb, 20)
on conflict (q) do update set prompt = excluded.prompt, options = excluded.options, seconds = excluded.seconds;

insert into quiz_key (q, answer, explain) values
  (1, 1, 'Task. The verb is what you want done; persona, context and format make it better.'),
  (2, 2, '78.7%. Five words, +61 points (Kojima et al., 2022).'),
  (3, 3, 'Tags. Labelling your content keeps it separate from your instructions.'),
  (4, 0, 'Verify it. Made-up facts and sources are called hallucinations.'),
  (5, 2, 'Model Context Protocol, the open standard released by Anthropic in November 2024.'),
  (6, 3, 'USB-C port. One standard plug, lots of devices.'),
  (7, 0, 'MCP = hands, Skills = know-how.'),
  (8, 1, 'About 4 characters, roughly ¾ of an English word.'),
  (9, 2, 'The whole history rides along, so new topic, new chat.'),
  (10, 3, '5×. That''s why "keep it short" saves real money.'),
  (11, 2, '10 tokens: super · cal · if · rag · il · istic · exp · ial · id · ocious. Rare words get chopped into pieces.')
on conflict (q) do update set answer = excluded.answer, explain = excluded.explain;

-- ---------------------------------------------------------------------
-- Access: phones may read the game state and the questions. Everything
-- else goes through the functions below.
-- ---------------------------------------------------------------------
alter table quiz_secret    enable row level security;
alter table quiz_state     enable row level security;
alter table quiz_questions enable row level security;
alter table quiz_key       enable row level security;
alter table quiz_players   enable row level security;
alter table quiz_answers   enable row level security;

drop policy if exists "read state" on quiz_state;
create policy "read state" on quiz_state for select to anon, authenticated using (true);
drop policy if exists "read questions" on quiz_questions;
create policy "read questions" on quiz_questions for select to anon, authenticated using (true);
grant select on quiz_state, quiz_questions to anon, authenticated;

-- Phones get pushed state changes over Realtime
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and tablename = 'quiz_state') then
    alter publication supabase_realtime add table quiz_state;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Presenter functions (need the PIN)
-- ---------------------------------------------------------------------
create or replace function quiz_pin_ok(p_pin text) returns void
language plpgsql security definer set search_path = public as $$
declare v text;
begin
  select pin into v from quiz_secret where id = 1;
  if v is null or v = 'CHANGE-ME' then
    raise exception 'Set a presenter PIN first: update quiz_secret set pin = ''your-pin'';';
  end if;
  if p_pin is distinct from v then
    raise exception 'Wrong presenter PIN';
  end if;
end $$;

-- p_action: check | new | open | close | reveal | done
create or replace function quiz_control(p_pin text, p_action text, p_q int default null)
returns json
language plpgsql security definer set search_path = public as $$
declare st quiz_state;
begin
  perform quiz_pin_ok(p_pin);
  if p_action = 'check' then
    null;
  elsif p_action = 'new' then
    update quiz_state
       set session = to_char(now() at time zone 'Asia/Kuala_Lumpur', 'YYYYMMDD-HH24MISS'),
           q = 0, phase = 'lobby', opened_at = null, updated_at = now()
     where id = 1;
  elsif p_action = 'open' then
    if not exists (select 1 from quiz_questions where q = p_q) then
      raise exception 'No question %', p_q;
    end if;
    update quiz_state set q = p_q, phase = 'open', opened_at = now(), updated_at = now() where id = 1;
  elsif p_action = 'close' then
    update quiz_state set phase = 'closed', updated_at = now() where id = 1 and q = p_q and phase = 'open';
  elsif p_action = 'reveal' then
    update quiz_state set q = p_q, phase = 'revealed', updated_at = now() where id = 1;
  elsif p_action = 'done' then
    update quiz_state set phase = 'done', updated_at = now() where id = 1;
  else
    raise exception 'Unknown action %', p_action;
  end if;
  select * into st from quiz_state where id = 1;
  return row_to_json(st);
end $$;

-- Who has joined the current game (newest first)
create or replace function quiz_lobby(p_pin text)
returns json
language plpgsql security definer set search_path = public as $$
declare st quiz_state;
begin
  perform quiz_pin_ok(p_pin);
  select * into st from quiz_state where id = 1;
  return json_build_object(
    'session', st.session,
    'count', (select count(*) from quiz_players where session = st.session and not hidden),
    'players', coalesce((
      select json_agg(json_build_object('id', z.id, 'name', z.name) order by z.created_at desc)
      from (select id, name, created_at from quiz_players
            where session = st.session and not hidden
            order by created_at desc limit 40) z), '[]'::json));
end $$;

-- Leaderboard for the current game
create or replace function quiz_board(p_pin text, p_limit int default 10)
returns json
language plpgsql security definer set search_path = public as $$
declare st quiz_state;
begin
  perform quiz_pin_ok(p_pin);
  select * into st from quiz_state where id = 1;
  return coalesce((
    select json_agg(r order by r.score desc, r.correct desc, r.joined)
    from (select p.id, p.name, p.created_at as joined,
                 coalesce(sum(a.points), 0)::int as score,
                 (count(*) filter (where a.correct))::int as correct
          from quiz_players p
          left join quiz_answers a on a.player_id = p.id
          where p.session = st.session and not p.hidden
          group by p.id
          order by score desc, correct desc, p.created_at
          limit p_limit) r), '[]'::json);
end $$;

-- Remove a player (for rude names). Their answers stop counting.
create or replace function quiz_kick(p_pin text, p_player uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  perform quiz_pin_ok(p_pin);
  update quiz_players set hidden = true where id = p_player;
end $$;

-- ---------------------------------------------------------------------
-- Phone functions
-- ---------------------------------------------------------------------
create or replace function quiz_join(p_name text)
returns json
language plpgsql security definer set search_path = public as $$
declare
  n   text := btrim(left(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'), 24));
  st  quiz_state;
  pid uuid;
begin
  if length(n) < 1 then
    raise exception 'Enter a name';
  end if;
  select * into st from quiz_state where id = 1;
  insert into quiz_players (session, name) values (st.session, n) returning id into pid;
  return json_build_object('player_id', pid, 'session', st.session, 'name', n);
end $$;

-- Returns: ok | duplicate | closed | rejoin | removed | invalid
create or replace function quiz_answer(p_player uuid, p_q int, p_choice int)
returns text
language plpgsql security definer set search_path = public as $$
declare
  st   quiz_state;
  pl   quiz_players;
  ans  int;
  secs int;
  ms   int;
  ok   boolean;
  pts  int;
begin
  select * into st from quiz_state where id = 1;
  select * into pl from quiz_players where id = p_player;
  if not found or pl.session <> st.session then return 'rejoin'; end if;
  if pl.hidden then return 'removed'; end if;
  if st.q <> p_q or st.phase <> 'open' then return 'closed'; end if;
  if p_choice is null or p_choice not between 0 and 3 then return 'invalid'; end if;

  select answer into ans from quiz_key where q = p_q;
  select seconds into secs from quiz_questions where q = p_q;
  ms  := greatest(0, floor(extract(epoch from (clock_timestamp() - st.opened_at)) * 1000))::int;
  ok  := (ans = p_choice);
  -- Correct answers score 500–1000: the faster, the more
  pts := case when ok then 500 + round(500 * greatest(0, 1 - ms / (secs * 1000.0)))::int else 0 end;

  insert into quiz_answers (player_id, q, choice, correct, points, ms)
  values (p_player, p_q, p_choice, ok, pts, ms)
  on conflict (player_id, q) do nothing;
  if not found then return 'duplicate'; end if;
  return 'ok';
end $$;

-- The player's view: current question status, and (after the reveal)
-- whether they were right, plus running total and rank. Points for the
-- current question stay hidden until it is revealed.
create or replace function quiz_me(p_player uuid)
returns json
language plpgsql security definer set search_path = public as $$
declare
  st       quiz_state;
  pl       quiz_players;
  a        quiz_answers;
  k        quiz_key;
  shown    boolean;
  answered boolean;
  total    int;
  rnk      int;
  players  int;
begin
  select * into st from quiz_state where id = 1;
  select * into pl from quiz_players where id = p_player;
  if not found or pl.session <> st.session then
    return json_build_object('status', 'rejoin');
  end if;
  if pl.hidden then
    return json_build_object('status', 'removed');
  end if;

  shown := st.phase in ('revealed', 'done');
  select * into a from quiz_answers where player_id = p_player and q = st.q;
  answered := found;
  if shown then
    select * into k from quiz_key where q = st.q;
  end if;

  select coalesce(sum(points), 0) into total
    from quiz_answers where player_id = p_player and (shown or q <> st.q);
  select count(*) filter (where t.s > total) + 1, count(*) into rnk, players
    from (select coalesce(sum(x.points) filter (where shown or x.q <> st.q), 0) as s
            from quiz_players p
            left join quiz_answers x on x.player_id = p.id
           where p.session = st.session and not p.hidden
           group by p.id) t;

  return json_build_object(
    'status',   'ok',
    'name',     pl.name,
    'q',        st.q,
    'phase',    st.phase,
    'answered', answered,
    'choice',   a.choice,
    'correct',  case when shown and answered then a.correct end,
    'points',   case when shown and answered then a.points end,
    'answer',   case when shown then k.answer end,
    'explain',  case when shown then k.explain end,
    'total',    total,
    'rank',     rnk,
    'players',  players);
end $$;

-- Answers in for a question (shown live on the deck)
create or replace function quiz_count(p_q int)
returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'answers', (select count(*) from quiz_answers a
                  join quiz_players p on p.id = a.player_id
                  join quiz_state s on s.id = 1
                 where p.session = s.session and not p.hidden and a.q = p_q),
    'players', (select count(*) from quiz_players p
                  join quiz_state s on s.id = 1
                 where p.session = s.session and not p.hidden));
$$;

-- ---------------------------------------------------------------------
-- Who may call what
-- ---------------------------------------------------------------------
revoke all on function quiz_pin_ok(text) from public, anon, authenticated;
grant execute on function
  quiz_control(text, text, int),
  quiz_lobby(text),
  quiz_board(text, int),
  quiz_kick(text, uuid),
  quiz_join(text),
  quiz_answer(uuid, int, int),
  quiz_me(uuid),
  quiz_count(int)
to anon, authenticated;
