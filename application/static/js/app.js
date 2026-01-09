/**
 * Bibliofile - Interactive Library Application
 * JavaScript functionality for ratings, reviews, and UI interactions
 */

document.addEventListener('DOMContentLoaded', function() {
    initializeStarRating();
    initializeAnimations();
});

/**
 * Initialize star rating functionality
 */
function initializeStarRating() {
    const starRatings = document.querySelectorAll('.star-rating');

    starRatings.forEach(container => {
        const bookId = container.dataset.bookId;
        const stars = container.querySelectorAll('.rate-star');

        stars.forEach((star, index) => {
            // Hover effects
            star.addEventListener('mouseenter', () => {
                highlightStars(stars, index + 1);
            });

            star.addEventListener('mouseleave', () => {
                resetStars(stars);
            });

            // Click to rate
            star.addEventListener('click', () => {
                const rating = parseInt(star.dataset.rating);
                submitRating(bookId, rating, stars);
            });
        });
    });
}

/**
 * Highlight stars up to the specified count
 */
function highlightStars(stars, count) {
    stars.forEach((star, index) => {
        if (index < count) {
            star.classList.add('active');
        } else {
            star.classList.remove('active');
        }
    });
}

/**
 * Reset all stars to default state
 */
function resetStars(stars) {
    stars.forEach(star => {
        star.classList.remove('active');
    });
}

/**
 * Submit a rating to the server
 */
function submitRating(bookId, rating, stars) {
    fetch('/api/rate', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({
            book_id: parseInt(bookId),
            rating: rating
        })
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            // Show success feedback
            showNotification(`Thank you! You rated this book ${rating} star${rating > 1 ? 's' : ''}.`);

            // Update displayed rating
            updateDisplayedRating(data.new_rating, data.count);

            // Keep stars highlighted
            highlightStars(stars, rating);
        } else {
            showNotification('Failed to submit rating. Please try again.', 'error');
        }
    })
    .catch(error => {
        console.error('Error:', error);
        showNotification('An error occurred. Please try again.', 'error');
    });
}

/**
 * Update the displayed rating on the page
 */
function updateDisplayedRating(newRating, count) {
    const ratingNumber = document.querySelector('.rating-number');
    const ratingCount = document.querySelector('.rating-count');

    if (ratingNumber) {
        ratingNumber.textContent = newRating;
    }

    if (ratingCount) {
        ratingCount.textContent = `(${count} ratings)`;
    }
}

/**
 * Show a notification to the user
 */
function showNotification(message, type = 'success') {
    // Remove existing notifications
    const existing = document.querySelector('.notification');
    if (existing) {
        existing.remove();
    }

    // Create notification element
    const notification = document.createElement('div');
    notification.className = `notification notification-${type}`;
    notification.innerHTML = `
        <span class="notification-message">${message}</span>
        <button class="notification-close">&times;</button>
    `;

    // Add styles
    notification.style.cssText = `
        position: fixed;
        bottom: 2rem;
        right: 2rem;
        background: ${type === 'success' ? '#2d4a3e' : '#722f37'};
        color: #f5f0e6;
        padding: 1rem 1.5rem;
        border-radius: 8px;
        box-shadow: 0 8px 40px rgba(26, 20, 16, 0.2);
        display: flex;
        align-items: center;
        gap: 1rem;
        z-index: 1000;
        animation: slideIn 0.3s ease-out;
    `;

    // Add animation keyframes if not already present
    if (!document.querySelector('#notification-styles')) {
        const style = document.createElement('style');
        style.id = 'notification-styles';
        style.textContent = `
            @keyframes slideIn {
                from {
                    opacity: 0;
                    transform: translateX(100%);
                }
                to {
                    opacity: 1;
                    transform: translateX(0);
                }
            }
            @keyframes slideOut {
                from {
                    opacity: 1;
                    transform: translateX(0);
                }
                to {
                    opacity: 0;
                    transform: translateX(100%);
                }
            }
            .notification-close {
                background: none;
                border: none;
                color: inherit;
                font-size: 1.5rem;
                cursor: pointer;
                opacity: 0.7;
                transition: opacity 0.2s;
            }
            .notification-close:hover {
                opacity: 1;
            }
        `;
        document.head.appendChild(style);
    }

    document.body.appendChild(notification);

    // Close button functionality
    notification.querySelector('.notification-close').addEventListener('click', () => {
        removeNotification(notification);
    });

    // Auto-remove after 5 seconds
    setTimeout(() => {
        removeNotification(notification);
    }, 5000);
}

/**
 * Remove a notification with animation
 */
function removeNotification(notification) {
    if (notification && notification.parentNode) {
        notification.style.animation = 'slideOut 0.3s ease-out forwards';
        setTimeout(() => {
            notification.remove();
        }, 300);
    }
}

/**
 * Initialize scroll-triggered animations
 */
function initializeAnimations() {
    // Intersection Observer for fade-in animations
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    // Observe elements with animation classes
    document.querySelectorAll('.book-card, .genre-card, .review-card, .browse-book-card, .search-result-card').forEach(el => {
        observer.observe(el);
    });
}

/**
 * Smooth scroll to element
 */
function scrollToElement(elementId) {
    const element = document.getElementById(elementId);
    if (element) {
        element.scrollIntoView({
            behavior: 'smooth',
            block: 'start'
        });
    }
}

/**
 * Toggle mobile navigation (if implemented)
 */
function toggleMobileNav() {
    const navLinks = document.querySelector('.nav-links');
    if (navLinks) {
        navLinks.classList.toggle('active');
    }
}

/**
 * Debounce function for search input
 */
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

/**
 * Live search functionality (optional enhancement)
 */
function initializeLiveSearch() {
    const searchInput = document.querySelector('.search-input');

    if (searchInput) {
        const debouncedSearch = debounce((query) => {
            if (query.length >= 2) {
                fetch(`/api/search?q=${encodeURIComponent(query)}`)
                    .then(response => response.json())
                    .then(data => {
                        // Update search suggestions if implemented
                        console.log('Search results:', data);
                    });
            }
        }, 300);

        searchInput.addEventListener('input', (e) => {
            debouncedSearch(e.target.value);
        });
    }
}
