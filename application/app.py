"""
Book Library Application - IMDB-style book rating and review platform
"""
from flask import Flask, render_template, request, jsonify, redirect, url_for
from datetime import datetime
import json
import os

app = Flask(__name__)

# In-memory database (in production, use a real database)
DATA_FILE = '/opt/book-library/data/books.json'

def load_data():
    """Load books data from file"""
    if os.path.exists(DATA_FILE):
        try:
            with open(DATA_FILE, 'r') as f:
                return json.load(f)
        except:
            pass
    return get_sample_books()

def save_data(data):
    """Save books data to file"""
    os.makedirs(os.path.dirname(DATA_FILE), exist_ok=True)
    with open(DATA_FILE, 'w') as f:
        json.dump(data, f, indent=2)

def get_sample_books():
    """Return sample book data"""
    return {
        "books": [
            {
                "id": 1,
                "title": "The Great Gatsby",
                "author": "F. Scott Fitzgerald",
                "year": 1925,
                "genre": "Classic Fiction",
                "cover": "https://covers.openlibrary.org/b/id/7222246-L.jpg",
                "description": "A story of decadence and excess, Gatsby explores the American Dream through the eyes of Nick Carraway in 1920s New York.",
                "rating": 4.5,
                "ratings_count": 2847,
                "reviews": [
                    {"user": "LiteraryLover", "rating": 5, "text": "A timeless masterpiece that captures the essence of the Jazz Age.", "date": "2024-01-15"},
                    {"user": "BookWorm42", "rating": 4, "text": "Beautiful prose and complex characters. Fitzgerald at his finest.", "date": "2024-01-10"}
                ]
            },
            {
                "id": 2,
                "title": "To Kill a Mockingbird",
                "author": "Harper Lee",
                "year": 1960,
                "genre": "Southern Gothic",
                "cover": "https://covers.openlibrary.org/b/id/8314136-L.jpg",
                "description": "Through the eyes of Scout Finch, we witness the injustice of racial prejudice in the American South.",
                "rating": 4.8,
                "ratings_count": 4521,
                "reviews": [
                    {"user": "ClassicReader", "rating": 5, "text": "Required reading for everyone. A powerful story about justice and compassion.", "date": "2024-02-01"},
                    {"user": "SouthernBelle", "rating": 5, "text": "Atticus Finch remains one of literature's greatest heroes.", "date": "2024-01-28"}
                ]
            },
            {
                "id": 3,
                "title": "1984",
                "author": "George Orwell",
                "year": 1949,
                "genre": "Dystopian Fiction",
                "cover": "https://covers.openlibrary.org/b/id/8575141-L.jpg",
                "description": "A chilling prophecy about the future, exploring themes of totalitarianism, surveillance, and the manipulation of truth.",
                "rating": 4.6,
                "ratings_count": 3892,
                "reviews": [
                    {"user": "DystopiaFan", "rating": 5, "text": "More relevant today than ever. A haunting and essential read.", "date": "2024-01-20"},
                    {"user": "ThoughtPolice", "rating": 4, "text": "Orwell's vision is terrifyingly prescient.", "date": "2024-01-18"}
                ]
            },
            {
                "id": 4,
                "title": "Pride and Prejudice",
                "author": "Jane Austen",
                "year": 1813,
                "genre": "Romance",
                "cover": "https://covers.openlibrary.org/b/id/12645114-L.jpg",
                "description": "The witty and romantic tale of Elizabeth Bennet and Mr. Darcy, navigating society and their own pride.",
                "rating": 4.7,
                "ratings_count": 3156,
                "reviews": [
                    {"user": "AustenFan", "rating": 5, "text": "The original romantic comedy. Austen's wit is unmatched.", "date": "2024-02-05"},
                    {"user": "RegencyReader", "rating": 5, "text": "Elizabeth and Darcy's love story never gets old.", "date": "2024-01-30"}
                ]
            },
            {
                "id": 5,
                "title": "The Catcher in the Rye",
                "author": "J.D. Salinger",
                "year": 1951,
                "genre": "Coming-of-Age",
                "cover": "https://covers.openlibrary.org/b/id/8231432-L.jpg",
                "description": "Holden Caulfield's journey through New York City, a classic tale of teenage angst and alienation.",
                "rating": 4.1,
                "ratings_count": 2234,
                "reviews": [
                    {"user": "TeenReader", "rating": 5, "text": "Holden perfectly captures the feeling of being a misunderstood teenager.", "date": "2024-01-25"},
                    {"user": "CriticalMind", "rating": 3, "text": "Overrated but still an important cultural touchstone.", "date": "2024-01-22"}
                ]
            },
            {
                "id": 6,
                "title": "One Hundred Years of Solitude",
                "author": "Gabriel García Márquez",
                "year": 1967,
                "genre": "Magical Realism",
                "cover": "https://covers.openlibrary.org/b/id/8701238-L.jpg",
                "description": "The multi-generational story of the Buendía family in the mythical town of Macondo.",
                "rating": 4.4,
                "ratings_count": 1876,
                "reviews": [
                    {"user": "MagicLover", "rating": 5, "text": "A sweeping epic that blends reality and fantasy seamlessly.", "date": "2024-02-08"},
                    {"user": "LatinLit", "rating": 4, "text": "Complex but rewarding. García Márquez is a master storyteller.", "date": "2024-02-02"}
                ]
            },
            {
                "id": 7,
                "title": "The Hobbit",
                "author": "J.R.R. Tolkien",
                "year": 1937,
                "genre": "Fantasy",
                "cover": "https://covers.openlibrary.org/b/id/8406786-L.jpg",
                "description": "Bilbo Baggins embarks on an unexpected journey with a company of dwarves to reclaim their homeland.",
                "rating": 4.8,
                "ratings_count": 4102,
                "reviews": [
                    {"user": "FantasyFan", "rating": 5, "text": "The book that started it all. A perfect adventure story.", "date": "2024-02-10"},
                    {"user": "MiddleEarthLover", "rating": 5, "text": "Tolkien's world-building is unparalleled.", "date": "2024-02-06"}
                ]
            },
            {
                "id": 8,
                "title": "Crime and Punishment",
                "author": "Fyodor Dostoevsky",
                "year": 1866,
                "genre": "Psychological Fiction",
                "cover": "https://covers.openlibrary.org/b/id/8235528-L.jpg",
                "description": "Raskolnikov's moral dilemmas after committing murder, a profound exploration of guilt and redemption.",
                "rating": 4.3,
                "ratings_count": 1543,
                "reviews": [
                    {"user": "RussianLit", "rating": 5, "text": "Dostoevsky dissects the human psyche like no other.", "date": "2024-01-29"},
                    {"user": "PhilosophyBuff", "rating": 4, "text": "Dense but deeply rewarding. A masterwork of psychological literature.", "date": "2024-01-26"}
                ]
            }
        ],
        "next_id": 9
    }

# Initialize data
books_data = load_data()

@app.route('/')
def home():
    """Home page with featured books"""
    data = load_data()
    featured = sorted(data['books'], key=lambda x: x['rating'], reverse=True)[:6]
    recent = sorted(data['books'], key=lambda x: x['id'], reverse=True)[:4]
    return render_template('index.html', featured=featured, recent=recent, all_books=data['books'])

@app.route('/book/<int:book_id>')
def book_detail(book_id):
    """Book detail page"""
    data = load_data()
    book = next((b for b in data['books'] if b['id'] == book_id), None)
    if not book:
        return redirect(url_for('home'))

    # Get similar books (same genre)
    similar = [b for b in data['books'] if b['genre'] == book['genre'] and b['id'] != book_id][:4]
    return render_template('book_detail.html', book=book, similar=similar)

@app.route('/browse')
def browse():
    """Browse all books"""
    data = load_data()
    genre = request.args.get('genre', 'all')
    sort_by = request.args.get('sort', 'rating')

    books = data['books']
    if genre != 'all':
        books = [b for b in books if b['genre'] == genre]

    if sort_by == 'rating':
        books = sorted(books, key=lambda x: x['rating'], reverse=True)
    elif sort_by == 'year':
        books = sorted(books, key=lambda x: x['year'], reverse=True)
    elif sort_by == 'title':
        books = sorted(books, key=lambda x: x['title'])

    genres = list(set(b['genre'] for b in data['books']))
    return render_template('browse.html', books=books, genres=genres, current_genre=genre, sort_by=sort_by)

@app.route('/add-book', methods=['GET', 'POST'])
def add_book():
    """Add a new book"""
    if request.method == 'POST':
        data = load_data()
        new_book = {
            "id": data['next_id'],
            "title": request.form['title'],
            "author": request.form['author'],
            "year": int(request.form['year']),
            "genre": request.form['genre'],
            "cover": request.form.get('cover', 'https://via.placeholder.com/300x450?text=No+Cover'),
            "description": request.form['description'],
            "rating": 0,
            "ratings_count": 0,
            "reviews": []
        }
        data['books'].append(new_book)
        data['next_id'] += 1
        save_data(data)
        return redirect(url_for('book_detail', book_id=new_book['id']))

    genres = ["Classic Fiction", "Southern Gothic", "Dystopian Fiction", "Romance",
              "Coming-of-Age", "Magical Realism", "Fantasy", "Psychological Fiction",
              "Science Fiction", "Mystery", "Horror", "Historical Fiction", "Biography"]
    return render_template('add_book.html', genres=genres)

@app.route('/api/rate', methods=['POST'])
def rate_book():
    """API endpoint to rate a book"""
    data = load_data()
    book_id = request.json.get('book_id')
    rating = request.json.get('rating')

    book = next((b for b in data['books'] if b['id'] == book_id), None)
    if book:
        # Calculate new average rating
        total = book['rating'] * book['ratings_count'] + rating
        book['ratings_count'] += 1
        book['rating'] = round(total / book['ratings_count'], 1)
        save_data(data)
        return jsonify({"success": True, "new_rating": book['rating'], "count": book['ratings_count']})

    return jsonify({"success": False, "error": "Book not found"}), 404

@app.route('/api/review', methods=['POST'])
def add_review():
    """API endpoint to add a review"""
    data = load_data()
    book_id = request.json.get('book_id')
    review_data = {
        "user": request.json.get('user', 'Anonymous'),
        "rating": request.json.get('rating'),
        "text": request.json.get('text'),
        "date": datetime.now().strftime("%Y-%m-%d")
    }

    book = next((b for b in data['books'] if b['id'] == book_id), None)
    if book:
        book['reviews'].insert(0, review_data)
        # Update rating
        total = book['rating'] * book['ratings_count'] + review_data['rating']
        book['ratings_count'] += 1
        book['rating'] = round(total / book['ratings_count'], 1)
        save_data(data)
        return jsonify({"success": True, "review": review_data})

    return jsonify({"success": False, "error": "Book not found"}), 404

@app.route('/search')
def search():
    """Search for books"""
    query = request.args.get('q', '').lower()
    data = load_data()

    if query:
        results = [b for b in data['books']
                   if query in b['title'].lower()
                   or query in b['author'].lower()
                   or query in b['genre'].lower()]
    else:
        results = []

    return render_template('search.html', results=results, query=query)

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
