-- بانک طرح درس نماز: کل این فایل را یک‌جا در Supabase > SQL Editor بچسبانید و Run بزنید.
-- اجرای دوباره آن بی‌خطر است (چیزی تکراری ساخته نمی‌شود).

create table if not exists public.categories(
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references public.categories(id) on delete cascade,
  name text not null, description text, sort int default 0,
  created_at timestamptz default now());
create table if not exists public.contents(
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete cascade,
  title text not null, type text not null default 'سایر',
  summary text, objective text, body text, age_group text, duration text, materials text,
  source text, source_url text, notes text, tags text[] default '{}',
  created_at timestamptz default now());
create index if not exists contents_cat on public.contents(category_id);
create table if not exists public.admins(user_id uuid primary key references auth.users(id) on delete cascade);

alter table public.categories enable row level security;
alter table public.contents enable row level security;
alter table public.admins enable row level security;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.admins where user_id=auth.uid()) $$;

-- اولین کاربری که ساخته شود خودکار مدیر می‌شود
create or replace function public.first_admin() returns trigger language plpgsql security definer set search_path=public
as $$ begin if not exists(select 1 from public.admins) then insert into public.admins values(new.id); end if; return new; end $$;
drop trigger if exists t_first_admin on auth.users;
create trigger t_first_admin after insert on auth.users for each row execute function public.first_admin();
insert into public.admins select id from auth.users where not exists(select 1 from public.admins) order by created_at limit 1;

drop policy if exists "read categories" on public.categories;
drop policy if exists "admin categories" on public.categories;
drop policy if exists "read contents" on public.contents;
drop policy if exists "admin contents" on public.contents;
create policy "read categories" on public.categories for select using (true);
create policy "admin categories" on public.categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "read contents" on public.contents for select using (true);
create policy "admin contents" on public.contents for all to authenticated using (public.is_admin()) with check (public.is_admin());

grant usage on schema public to anon, authenticated;
grant select on public.categories to anon, authenticated;
grant select, insert, update, delete on public.categories, public.contents to authenticated;
-- بازدیدکننده عادی «یادداشت شخصی» را نمی‌بیند؛ فقط مدیر می‌بیند
revoke select on public.contents from anon;
grant select (id,category_id,title,type,summary,objective,body,age_group,duration,materials,source,source_url,tags,created_at) on public.contents to anon;
grant execute on function public.is_admin() to anon, authenticated;

-- دسته‌بندی‌های اولیه (فقط اگر هنوز هیچ دسته‌ای وجود نداشته باشد)
create or replace function public.seed_tree(p uuid, n jsonb) returns void language plpgsql as $$
declare k jsonb; i int := 0; nid uuid;
begin
  for k in select * from jsonb_array_elements(n) loop
    i := i + 1;
    if jsonb_typeof(k) = 'string' then
      insert into public.categories(parent_id,name,sort) values (p, k #>> '{}', i);
    else
      insert into public.categories(parent_id,name,description,sort) values (p, k->>'n', k->>'d', i) returning id into nid;
      perform public.seed_tree(nid, k->'c');
    end if;
  end loop;
end $$;

do $do$ begin
if not exists (select 1 from public.categories) then
perform public.seed_tree(null, $j$[
{"n":"ارزش نماز را نمی‌دانند","d":"شناخت خدا، آثار نماز و چرایی نماز","c":[{"n":"شناخت خدا","c":["نعمت‌ها","خوف و رجا","ارتباط قلبی با خدا"]},"آثار نماز",{"n":"چرایی نماز","c":["چرا باید نماز بخوانیم؟","چرا خداوند نماز را واجب کرده است؟"]}]},
{"n":"ویژگی‌های شخصیتی","d":"ویژگی‌های روحی و اخلاقی که بر نماز اثر می‌گذارند","c":["لجبازی","تکبر","کمال‌گرایی","اعتمادبه‌نفس پایین","خجالت از نماز خواندن در جمع"]},
{"n":"خانواده","d":"نقش همراهی یا نبودِ همراهی خانواده","c":[{"n":"شناخت خانواده","c":[{"n":"خانواده همراه","c":["استفاده از همراهی خانواده","درخواست کمک از خانواده برای پیگیری نماز"]},{"n":"خانواده غیرهمراه","c":["پیدا کردن جایگزین برای حمایت خانوادگی","مسئول کردن خود بچه برای نماز و یادآوری نماز در خانواده","کمک گرفتن از خواهر یا برادر بزرگ‌تر","کمک گرفتن از دوستان مناسب"]}]}]},
{"n":"جذابیت‌های نماز","d":"داستان‌ها و برکات نماز اول وقت","c":["داستان‌های مرتبط با نماز","معجزه‌های نماز اول وقت","داستان شهدا و نماز اول وقت","اتفاقات و برکات نماز اول وقت در زندگی شهدا","عنوان داستان‌ها و روایت‌های مشخص"]},
{"n":"اولویت‌بندی برنامه‌های زندگی","d":"محور اصلی اعتکاف امسال: وقت و استفاده از فرصت‌ها","c":["ارزش وقت","وقت، امانت است","استفاده از فرصت‌ها","مدیریت زمان","اولویت‌بندی کارها","نماز به عنوان یک قرار ثابت با خدا"]},
{"n":"خوراک و مزاج","d":"اثر خوراک و مزاج بر کسالت و بیدار شدن برای نماز","c":["تأثیر خوراک و مزاج بر تنبلی","بی‌حالی و کسالت","سخت بیدار شدن برای نماز صبح"]},
{"n":"دوستان","d":"تأثیر دوستان و جمع بر نماز بچه‌ها","c":["شناخت بچه","دوستان همراه","دوستان نامناسب","تأثیرپذیری از دوستان","اعتمادبه‌نفس","فشار جمع","بازی و فراموش کردن نماز",{"n":"مسائل مربوط به دوستان","c":["نداشتن دوست همراه و مناسب","دوستانی که نماز نمی‌خوانند","خجالت از نماز خواندن جلوی دوستان","نماز نخواندن در مدرسه به خاطر دوستان","غرق شدن در بازی و وقت‌گذرانی با دوستان","فراموش کردن نماز به خاطر بازی و دوستان","قرار نگرفتن نماز در اولویت"]},{"n":"راهکارها","c":["کمرنگ کردن دوستی‌های نامناسب در صورت تأثیر منفی جدی","پیدا کردن دوستان همراه و نمازخوان","کار کردن روی اعتمادبه‌نفس بچه","نه گفتن به فشار جمع"]}]},
{"n":"سهل‌انگاری و تنبلی","d":"با دسته‌های دیگر هم‌پوشانی دارد","c":["سهل‌انگاری خود بچه","تنبلی","دوستی‌های نامناسب","ندانستن ارزش نماز","نداشتن اولویت‌بندی در زندگی","بی‌نظمی","خواب و بیداری نامناسب","نداشتن عادت منظم"]}
]$j$::jsonb);
end if;
end $do$;
drop function public.seed_tree(uuid, jsonb);
