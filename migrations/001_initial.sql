CREATE TABLE pies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    prediction TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO pies (prediction) VALUES
    ('Сегодня повезёт'),
    ('Скоро тебя ждёт приятная встреча'),
    ('Новая идея окажется удачной'),
    ('Хорошая новость уже в пути'),
    ('Неожиданный разговор поднимет настроение'),
    ('Найдётся время для любимого дела'),
    ('Маленький шаг приведёт к большой перемене'),
    ('Кто-то вспомнит о тебе с теплом'),
    ('Завтра будет повод улыбнуться');
