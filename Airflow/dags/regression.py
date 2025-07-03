import pandas as pd
import pendulum
import time
import pickle
from sklearn.datasets import make_regression
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.preprocessing import StandardScaler
from sklearn import metrics
from airflow.models.dag import DAG
from airflow.operators.python import PythonOperator

def create_dataset():
    X, y = make_regression(n_samples=1000, n_features=5, noise=0.1, random_state=42)
    df = pd.DataFrame(data=X, columns=[f'feature_{i}' for i in range(5)])
    df['target'] = y
    print("Dataset created with shape:", df.shape)
    df.to_csv('/tmp/regression_data.csv', index=False)

def preprocess_data():
    print("Starting data preprocessing...")
    time.sleep(5)

    df = pd.read_csv('/tmp/regression_data.csv')

    # Feature engineering с паузами
    print("Performing feature engineering...")
    time.sleep(5)

    # Создаем дополнительные фичи
    df['feature_interaction'] = df['feature_0'] * df['feature_1']
    df['feature_squared'] = df['feature_0'] ** 2

    print("Scaling features...")
    time.sleep(5)

    # Масштабирование
    feature_cols = [col for col in df.columns if col != 'target']
    scaler = StandardScaler()
    df[feature_cols] = scaler.fit_transform(df[feature_cols])

    df.to_csv('/tmp/preprocessed_data.csv', index=False)

    # Сохраняем скейлер
    with open('/tmp/scaler.pkl', 'wb') as f:
        pickle.dump(scaler, f)

    print("Preprocessing completed!")

def train_and_validate():
    print("Starting model training and validation...")
    time.sleep(5)

    df = pd.read_csv('/tmp/preprocessed_data.csv')
    feature_cols = [col for col in df.columns if col != 'target']
    X = df[feature_cols]
    y = df['target']

    # Разделение на train/test
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

    print("Training model...")
    time.sleep(10)

    model = LinearRegression()
    model.fit(X_train, y_train)

    print("Performing cross-validation...")
    time.sleep(5)

    # Cross-validation
    cv_scores = cross_val_score(model, X_train, y_train, cv=5, scoring='r2')

    # Предсказания
    y_pred = model.predict(X_test)

    print(f"Cross-validation R2 scores: {cv_scores}")
    print(f"Mean CV R2: {cv_scores.mean():.4f} (+/- {cv_scores.std() * 2:.4f})")
    print(f"Test MSE: {metrics.mean_squared_error(y_test, y_pred):.4f}")
    print(f"Test R2: {metrics.r2_score(y_test, y_pred):.4f}")

    # Сохраняем модель
    with open('/tmp/trained_model.pkl', 'wb') as f:
        pickle.dump(model, f)

    time.sleep(5)
    print("Model training and validation completed!")

def evaluate_model():
    print("Starting final model evaluation...")
    time.sleep(5)

    # Загружаем модель
    with open('/tmp/trained_model.pkl', 'rb') as f:
        model = pickle.load(f)

    df = pd.read_csv('/tmp/preprocessed_data.csv')
    feature_cols = [col for col in df.columns if col != 'target']
    X = df[feature_cols]
    y = df['target']

    print("Generating predictions...")
    time.sleep(10)

    predictions = model.predict(X)

    print("Calculating additional metrics...")
    time.sleep(5)

    mae = metrics.mean_absolute_error(y, predictions)
    mse = metrics.mean_squared_error(y, predictions)
    r2 = metrics.r2_score(y, predictions)

    print(f"Final Model Metrics:")
    print(f"MAE: {mae:.4f}")
    print(f"MSE: {mse:.4f}")
    print(f"R2: {r2:.4f}")

    # Сохраняем метрики
    metrics_dict = {'mae': mae, 'mse': mse, 'r2': r2}
    pd.Series(metrics_dict).to_csv('/tmp/model_metrics.csv')

    print("Model evaluation completed!")

dag = DAG(
    'ml_regression_pipeline',
    start_date=pendulum.datetime(2024, 1, 1, tz="UTC"),
    catchup=False
)

create_data = PythonOperator(
    task_id='create_dataset',
    python_callable=create_dataset,
    dag=dag
)

preprocess = PythonOperator(
    task_id='preprocess_data',
    python_callable=preprocess_data,
    dag=dag
)

train_model = PythonOperator(
    task_id='train_and_validate',
    python_callable=train_and_validate,
    dag=dag
)

evaluate = PythonOperator(
    task_id='evaluate_model',
    python_callable=evaluate_model,
    dag=dag
)

create_data >> preprocess >> train_model >> evaluate
